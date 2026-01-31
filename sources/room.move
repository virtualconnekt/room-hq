/// ============================================================
/// MODULE: Room
/// SPEC: EXECUTION_TASKS_BY_PHASE.md Section 2.2
/// INVARIANTS ENFORCED:
///   - INVARIANT_ROOM_001: Valid state transitions only
///   - INVARIANT_ROOM_004: Settled is terminal state
///   - INVARIANT_SUBMISSION_001: One submission per contributor
/// PURPOSE: Core room lifecycle and submission management
/// ============================================================
module aptosroom::room {
    use std::signer;
    use std::string::String;
    use std::option::{Self, Option};
    use std::vector;
    use aptos_std::table::{Self, Table};
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use aptosroom::errors;
    use aptosroom::constants;
    use aptosroom::keycard;
    use aptosroom::vault;

    // Friend declarations
    friend aptosroom::jury;
    friend aptosroom::variance;
    friend aptosroom::aggregation;
    friend aptosroom::settlement;

    // ============================================================
    // STRUCTS
    // ============================================================

    /// Main room resource
    struct Room has key, store {
        /// Unique room identifier
        id: u64,
        /// Client who created the room
        client: address,
        /// Category for juror matching
        category: String,
        /// Task description hash (IPFS or similar)
        task_hash: vector<u8>,
        /// Reward amount in APT
        task_reward: u64,
        /// Current state (0-6)
        state: u8,
        /// Submission deadline (block height)
        deadline_submit: u64,
        /// Jury commit deadline (block height)
        deadline_jury_commit: u64,
        /// Jury reveal deadline (block height)
        deadline_jury_reveal: u64,
        /// Submissions: contributor address -> Submission
        submissions: Table<address, Submission>,
        /// List of contributor addresses (for iteration)
        contributor_list: vector<address>,
        /// Selected jury pool
        jury_pool: vector<address>,
        /// Votes: juror address -> Vote
        votes: Table<address, Vote>,
        /// Whether jury score has been computed
        jury_score_computed: bool,
        /// Computed jury score (median)
        jury_score: u64,
        /// Final scores: contributor address -> final_score
        final_scores: Table<address, u64>,
        /// Whether client has approved settlement
        client_approved: bool,
        /// Winner address (set during settlement)
        winner: Option<address>,
        /// Created timestamp
        created_at: u64,
    }

    /// Submission from a contributor
    struct Submission has store {
        /// Contributor address
        contributor: address,
        /// Submission data hash (IPFS or similar)
        data_hash: vector<u8>,
        /// Submission timestamp
        submitted_at: u64,
        /// Client score (0-100, set during finalization)
        client_score: Option<u64>,
    }

    /// Vote from a juror (commit-reveal)
    struct Vote has store {
        /// Juror address
        juror: address,
        /// Committed hash: SHA3(score || salt)
        score_commit: vector<u8>,
        /// Whether vote has been revealed
        revealed: bool,
        /// Revealed score (after reveal)
        revealed_score: Option<u64>,
        /// Revealed salt (after reveal)
        revealed_salt: Option<vector<u8>>,
        /// Commit timestamp
        committed_at: u64,
        /// Whether flagged for variance
        variance_flagged: bool,
    }

    /// Global room counter and registry
    struct RoomRegistry has key {
        next_id: u64,
        /// Map of room_id -> creator address
        rooms: Table<u64, address>,
    }

    // ============================================================
    // EVENTS
    // ============================================================

    #[event]
    struct RoomCreated has drop, store {
        room_id: u64,
        client: address,
        category: String,
        task_reward: u64,
        timestamp: u64,
    }

    #[event]
    struct RoomStateChanged has drop, store {
        room_id: u64,
        from_state: u8,
        to_state: u8,
        timestamp: u64,
    }

    #[event]
    struct SubmissionCreated has drop, store {
        room_id: u64,
        contributor: address,
        timestamp: u64,
    }

    // ============================================================
    // INITIALIZATION
    // ============================================================

    /// Initialize room registry (called once at module publish)
    fun init_module(account: &signer) {
        move_to(account, RoomRegistry {
            next_id: 1,
            rooms: table::new<u64, address>(),
        });
    }

    // ============================================================
    // STATE MACHINE VALIDATION
    // ============================================================

    /// Valid state transitions (INVARIANT_ROOM_001)
    /// INIT(0) -> OPEN(1) -> CLOSED(2) -> JURY_ACTIVE(3) -> JURY_REVEAL(4) -> FINALIZED(5) -> SETTLED(6)
    fun is_valid_transition(from: u8, to: u8): bool {
        if (from == constants::STATE_INIT() && to == constants::STATE_OPEN()) { true }
        else if (from == constants::STATE_OPEN() && to == constants::STATE_CLOSED()) { true }
        else if (from == constants::STATE_CLOSED() && to == constants::STATE_JURY_ACTIVE()) { true }
        else if (from == constants::STATE_JURY_ACTIVE() && to == constants::STATE_JURY_REVEAL()) { true }
        else if (from == constants::STATE_JURY_REVEAL() && to == constants::STATE_FINALIZED()) { true }
        else if (from == constants::STATE_FINALIZED() && to == constants::STATE_SETTLED()) { true }
        else { false }
    }

    /// Check if state is terminal (INVARIANT_ROOM_004)
    fun is_terminal_state(state: u8): bool {
        state == constants::STATE_SETTLED()
    }

    /// Count committed votes (since table has no length function)
    fun count_committed_votes(room: &Room): u64 {
        let count = 0u64;
        let i = 0;
        let len = vector::length(&room.jury_pool);
        while (i < len) {
            let juror = *vector::borrow(&room.jury_pool, i);
            if (table::contains(&room.votes, juror)) {
                count = count + 1;
            };
            i = i + 1;
        };
        count
    }

    // ============================================================
    // PUBLIC ENTRY FUNCTIONS
    // ============================================================

    /// Create a new room
    /// Requires: caller has keycard, provides sufficient escrow
    public entry fun create_room(
        account: &signer,
        category: String,
        task_hash: vector<u8>,
        task_reward: u64,
        deadline_submit: u64,
        deadline_jury_commit: u64,
        deadline_jury_reveal: u64,
    ) acquires RoomRegistry {
        let client = signer::address_of(account);

        // Assert caller has keycard
        assert!(keycard::has_keycard(client), errors::E_KEYCARD_NOT_FOUND());

        // Get next room ID
        let registry = borrow_global_mut<RoomRegistry>(@aptosroom);
        let room_id = registry.next_id;
        registry.next_id = room_id + 1;

        // Withdraw coins for escrow
        let deposit = coin::withdraw<AptosCoin>(account, task_reward);

        // Create vault with deposit
        vault::create_vault(client, room_id, deposit, task_reward);

        // Create room with state = STATE_INIT
        let room = Room {
            id: room_id,
            client,
            category,
            task_hash,
            task_reward,
            state: constants::STATE_INIT(),
            deadline_submit,
            deadline_jury_commit,
            deadline_jury_reveal,
            submissions: table::new<address, Submission>(),
            contributor_list: vector::empty<address>(),
            jury_pool: vector::empty<address>(),
            votes: table::new<address, Vote>(),
            jury_score_computed: false,
            jury_score: 0,
            final_scores: table::new<address, u64>(),
            client_approved: false,
            winner: option::none<address>(),
            created_at: timestamp::now_seconds(),
        };

        // Store room at client's address
        move_to(account, room);

        // Add to registry
        table::add(&mut registry.rooms, room_id, client);

        // Emit event
        event::emit(RoomCreated {
            room_id,
            client,
            category,
            task_reward,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Open room for submissions (INIT -> OPEN)
    public entry fun open_room(account: &signer, room_id: u64) acquires RoomRegistry, Room {
        let caller = signer::address_of(account);
        let registry = borrow_global<RoomRegistry>(@aptosroom);
        let room_owner = *table::borrow(&registry.rooms, room_id);

        // Borrow room
        let room = borrow_global_mut<Room>(room_owner);

        // Assert caller is client
        assert!(room.client == caller, errors::E_NOT_CLIENT());

        // Assert valid transition
        let from_state = room.state;
        let to_state = constants::STATE_OPEN();
        assert!(is_valid_transition(from_state, to_state), errors::E_INVALID_STATE_TRANSITION());
        assert!(!is_terminal_state(from_state), errors::E_STATE_IS_TERMINAL());

        // Update state
        room.state = to_state;

        // Emit event
        event::emit(RoomStateChanged {
            room_id,
            from_state,
            to_state,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Submit work to room
    /// INVARIANT_SUBMISSION_001: One per contributor
    public entry fun submit_entry(
        account: &signer,
        room_id: u64,
        data_hash: vector<u8>,
    ) acquires RoomRegistry, Room {
        let contributor = signer::address_of(account);

        // Assert caller has keycard
        assert!(keycard::has_keycard(contributor), errors::E_KEYCARD_NOT_FOUND());

        let registry = borrow_global<RoomRegistry>(@aptosroom);
        let room_owner = *table::borrow(&registry.rooms, room_id);
        let room = borrow_global_mut<Room>(room_owner);

        // Assert room state == OPEN
        assert!(room.state == constants::STATE_OPEN(), errors::E_ROOM_NOT_OPEN());

        // Assert timestamp < deadline_submit
        assert!(
            timestamp::now_seconds() < room.deadline_submit,
            errors::E_DEADLINE_PASSED()
        );

        // Assert no duplicate submission (INVARIANT_SUBMISSION_001)
        assert!(
            !table::contains(&room.submissions, contributor),
            errors::E_DUPLICATE_SUBMISSION()
        );

        // Create submission
        let submission = Submission {
            contributor,
            data_hash,
            submitted_at: timestamp::now_seconds(),
            client_score: option::none<u64>(),
        };

        // Add to submissions
        table::add(&mut room.submissions, contributor, submission);
        vector::push_back(&mut room.contributor_list, contributor);

        // Emit event
        event::emit(SubmissionCreated {
            room_id,
            contributor,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Close room for submissions (OPEN -> CLOSED)
    public entry fun close_room(account: &signer, room_id: u64) acquires RoomRegistry, Room {
        let caller = signer::address_of(account);
        let registry = borrow_global<RoomRegistry>(@aptosroom);
        let room_owner = *table::borrow(&registry.rooms, room_id);
        let room = borrow_global_mut<Room>(room_owner);

        // Allow client to close early, or anyone after deadline
        let is_client = room.client == caller;
        let past_deadline = timestamp::now_seconds() >= room.deadline_submit;
        assert!(is_client || past_deadline, errors::E_NOT_CLIENT());

        // Assert valid transition
        let from_state = room.state;
        let to_state = constants::STATE_CLOSED();
        assert!(is_valid_transition(from_state, to_state), errors::E_INVALID_STATE_TRANSITION());

        // Update state
        room.state = to_state;

        // Emit event
        event::emit(RoomStateChanged {
            room_id,
            from_state,
            to_state,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Transition to jury active (CLOSED -> JURY_ACTIVE)
    public entry fun start_jury_phase(account: &signer, room_id: u64) acquires RoomRegistry, Room {
        let caller = signer::address_of(account);
        let registry = borrow_global<RoomRegistry>(@aptosroom);
        let room_owner = *table::borrow(&registry.rooms, room_id);
        let room = borrow_global_mut<Room>(room_owner);

        // Only client can start jury phase
        assert!(room.client == caller, errors::E_NOT_CLIENT());

        // Assert valid transition
        let from_state = room.state;
        let to_state = constants::STATE_JURY_ACTIVE();
        assert!(is_valid_transition(from_state, to_state), errors::E_INVALID_STATE_TRANSITION());

        // Jury should already be selected (non-empty pool)
        assert!(!vector::is_empty(&room.jury_pool), errors::E_JURY_NOT_SELECTED());

        // Update state
        room.state = to_state;

        // Emit event
        event::emit(RoomStateChanged {
            room_id,
            from_state,
            to_state,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Transition to reveal phase (JURY_ACTIVE -> JURY_REVEAL)
    public entry fun start_reveal_phase(account: &signer, room_id: u64) acquires RoomRegistry, Room {
        let caller = signer::address_of(account);
        let registry = borrow_global<RoomRegistry>(@aptosroom);
        let room_owner = *table::borrow(&registry.rooms, room_id);
        let room = borrow_global_mut<Room>(room_owner);

        // Only client can transition
        assert!(room.client == caller, errors::E_NOT_CLIENT());

        // Assert past commit deadline or all commits received
        // Count committed votes by checking each juror
        let past_deadline = timestamp::now_seconds() >= room.deadline_jury_commit;
        let all_committed = count_committed_votes(room) == vector::length(&room.jury_pool);
        assert!(past_deadline || all_committed, errors::E_COMMIT_PHASE_NOT_COMPLETE());

        // Assert valid transition
        let from_state = room.state;
        let to_state = constants::STATE_JURY_REVEAL();
        assert!(is_valid_transition(from_state, to_state), errors::E_INVALID_STATE_TRANSITION());

        // Update state
        room.state = to_state;

        // Emit event
        event::emit(RoomStateChanged {
            room_id,
            from_state,
            to_state,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Transition to finalized (JURY_REVEAL -> FINALIZED)
    public entry fun finalize_room(account: &signer, room_id: u64) acquires RoomRegistry, Room {
        let caller = signer::address_of(account);
        let registry = borrow_global<RoomRegistry>(@aptosroom);
        let room_owner = *table::borrow(&registry.rooms, room_id);
        let room = borrow_global_mut<Room>(room_owner);

        // Only client can finalize
        assert!(room.client == caller, errors::E_NOT_CLIENT());

        // Assert valid transition
        let from_state = room.state;
        let to_state = constants::STATE_FINALIZED();
        assert!(is_valid_transition(from_state, to_state), errors::E_INVALID_STATE_TRANSITION());

        // Note: Variance detection and score calculation done by aggregation module
        // before this transition

        // Update state
        room.state = to_state;

        // Emit event
        event::emit(RoomStateChanged {
            room_id,
            from_state,
            to_state,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Set client score for a submission
    public entry fun set_client_score(
        account: &signer,
        room_id: u64,
        contributor: address,
        score: u64,
    ) acquires RoomRegistry, Room {
        let caller = signer::address_of(account);
        let registry = borrow_global<RoomRegistry>(@aptosroom);
        let room_owner = *table::borrow(&registry.rooms, room_id);
        let room = borrow_global_mut<Room>(room_owner);

        // Assert caller is client
        assert!(room.client == caller, errors::E_NOT_CLIENT());

        // Assert score <= MAX_SCORE
        assert!(score <= constants::MAX_SCORE(), errors::E_INVALID_SCORE());

        // Set submission.client_score
        let submission = table::borrow_mut(&mut room.submissions, contributor);
        submission.client_score = option::some(score);
    }

    /// Submit work to room
    /// INVARIANT_SUBMISSION_001: One per contributor
    // TODO: Implement submit_entry(
    //   account: &signer,
    //   room_id: u64,
    //   data_hash: vector<u8>,
    // )
    // Steps:
    // 1. Assert caller has keycard (E_NO_KEYCARD)
    // 2. Assert room state == OPEN (E_ROOM_NOT_OPEN)
    // 3. Assert block_height < deadline_submit (E_DEADLINE_PASSED)
    // 4. Assert !table::contains(&room.submissions, contributor) (E_DUPLICATE_SUBMISSION)
    // 5. Create Submission struct
    // 6. Add to room.submissions
    // 7. Add contributor to contributor_list
    // 8. Emit SubmissionCreated event

    /// Close room for submissions (OPEN -> CLOSED)
    // TODO: Implement close_room(room_id: u64)
    // Steps:
    // 1. Assert block_height >= deadline_submit OR client calls
    // 2. Assert valid transition
    // 3. Update state
    // 4. Emit RoomStateChanged event

    /// Transition to jury active (CLOSED -> JURY_ACTIVE)
    // TODO: Implement start_jury_phase(room_id: u64)
    // Steps:
    // 1. Assert valid transition
    // 2. Jury should already be selected
    // 3. Update state
    // 4. Emit RoomStateChanged event

    /// Transition to reveal phase (JURY_ACTIVE -> JURY_REVEAL)
    // TODO: Implement start_reveal_phase(room_id: u64)
    // Steps:
    // 1. Assert block_height >= deadline_jury_commit OR all commits received
    // 2. Assert valid transition
    // 3. Update state
    // 4. Emit RoomStateChanged event

    /// Transition to finalized (JURY_REVEAL -> FINALIZED)
    // TODO: Implement finalize_scores(room_id: u64)
    // Steps:
    // 1. Assert all reveals complete or deadline passed
    // 2. Run variance detection
    // 3. Calculate jury score (median)
    // 4. Set jury_score_computed = true
    // 5. Update state
    // 6. Emit RoomStateChanged event

    /// Set client score for a submission
    // TODO: Implement set_client_score(
    //   account: &signer,
    //   room_id: u64,
    //   contributor: address,
    //   score: u64,
    // )
    // Steps:
    // 1. Assert caller is client (E_NOT_CLIENT)
    // 2. Assert score <= MAX_SCORE (E_INVALID_SCORE)
    // 3. Set submission.client_score

    // ============================================================
    // VIEW FUNCTIONS
    // ============================================================

    #[view]
    /// Get room state
    public fun get_state(room_id: u64): u8 acquires RoomRegistry, Room {
        let registry = borrow_global<RoomRegistry>(@aptosroom);
        let room_owner = *table::borrow(&registry.rooms, room_id);
        let room = borrow_global<Room>(room_owner);
        room.state
    }

    #[view]
    /// Get room client
    public fun get_client(room_id: u64): address acquires RoomRegistry, Room {
        let registry = borrow_global<RoomRegistry>(@aptosroom);
        let room_owner = *table::borrow(&registry.rooms, room_id);
        let room = borrow_global<Room>(room_owner);
        room.client
    }

    #[view]
    /// Check if contributor has submitted
    public fun has_submitted(room_id: u64, contributor: address): bool acquires RoomRegistry, Room {
        let registry = borrow_global<RoomRegistry>(@aptosroom);
        let room_owner = *table::borrow(&registry.rooms, room_id);
        let room = borrow_global<Room>(room_owner);
        table::contains(&room.submissions, contributor)
    }

    #[view]
    /// Get submission count
    public fun get_submission_count(room_id: u64): u64 acquires RoomRegistry, Room {
        let registry = borrow_global<RoomRegistry>(@aptosroom);
        let room_owner = *table::borrow(&registry.rooms, room_id);
        let room = borrow_global<Room>(room_owner);
        vector::length(&room.contributor_list)
    }

    #[view]
    /// Get jury pool
    public fun get_jury_pool(room_id: u64): vector<address> acquires RoomRegistry, Room {
        let registry = borrow_global<RoomRegistry>(@aptosroom);
        let room_owner = *table::borrow(&registry.rooms, room_id);
        let room = borrow_global<Room>(room_owner);
        room.jury_pool
    }

    #[view]
    /// Check if room is settled
    public fun is_settled(room_id: u64): bool acquires RoomRegistry, Room {
        let registry = borrow_global<RoomRegistry>(@aptosroom);
        let room_owner = *table::borrow(&registry.rooms, room_id);
        let room = borrow_global<Room>(room_owner);
        room.state == constants::STATE_SETTLED()
    }

    #[view]
    /// Get room category
    public fun get_category(room_id: u64): String acquires RoomRegistry, Room {
        let registry = borrow_global<RoomRegistry>(@aptosroom);
        let room_owner = *table::borrow(&registry.rooms, room_id);
        let room = borrow_global<Room>(room_owner);
        room.category
    }

    #[view]
    /// Get contributor list
    public fun get_contributor_list(room_id: u64): vector<address> acquires RoomRegistry, Room {
        let registry = borrow_global<RoomRegistry>(@aptosroom);
        let room_owner = *table::borrow(&registry.rooms, room_id);
        let room = borrow_global<Room>(room_owner);
        room.contributor_list
    }

    #[view]
    /// Check if room exists
    public fun room_exists(room_id: u64): bool acquires RoomRegistry {
        let registry = borrow_global<RoomRegistry>(@aptosroom);
        table::contains(&registry.rooms, room_id)
    }

    #[view]
    /// Get client score for contributor
    public fun get_client_score(room_id: u64, contributor: address): Option<u64> acquires RoomRegistry, Room {
        let registry = borrow_global<RoomRegistry>(@aptosroom);
        let room_owner = *table::borrow(&registry.rooms, room_id);
        let room = borrow_global<Room>(room_owner);
        let submission = table::borrow(&room.submissions, contributor);
        submission.client_score
    }

    #[view]
    /// Check if client has approved
    public fun is_client_approved(room_id: u64): bool acquires RoomRegistry, Room {
        let registry = borrow_global<RoomRegistry>(@aptosroom);
        let room_owner = *table::borrow(&registry.rooms, room_id);
        let room = borrow_global<Room>(room_owner);
        room.client_approved
    }

    #[view]
    /// Check if jury score is computed
    public fun is_jury_score_computed(room_id: u64): bool acquires RoomRegistry, Room {
        let registry = borrow_global<RoomRegistry>(@aptosroom);
        let room_owner = *table::borrow(&registry.rooms, room_id);
        let room = borrow_global<Room>(room_owner);
        room.jury_score_computed
    }

    #[view]
    /// Get jury score
    public fun get_jury_score(room_id: u64): u64 acquires RoomRegistry, Room {
        let registry = borrow_global<RoomRegistry>(@aptosroom);
        let room_owner = *table::borrow(&registry.rooms, room_id);
        let room = borrow_global<Room>(room_owner);
        room.jury_score
    }

    #[view]
    /// Get final score for contributor
    public fun get_final_score(room_id: u64, contributor: address): u64 acquires RoomRegistry, Room {
        let registry = borrow_global<RoomRegistry>(@aptosroom);
        let room_owner = *table::borrow(&registry.rooms, room_id);
        let room = borrow_global<Room>(room_owner);
        *table::borrow(&room.final_scores, contributor)
    }

    #[view]
    /// Get winner address
    public fun get_winner(room_id: u64): Option<address> acquires RoomRegistry, Room {
        let registry = borrow_global<RoomRegistry>(@aptosroom);
        let room_owner = *table::borrow(&registry.rooms, room_id);
        let room = borrow_global<Room>(room_owner);
        room.winner
    }

    // ============================================================
    // INTERNAL FUNCTIONS (for other modules via friend)
    // ============================================================

    /// Set jury pool (called by jury module)
    public(friend) fun set_jury_pool(room_id: u64, jurors: vector<address>) acquires RoomRegistry, Room {
        let registry = borrow_global<RoomRegistry>(@aptosroom);
        let room_owner = *table::borrow(&registry.rooms, room_id);
        let room = borrow_global_mut<Room>(room_owner);
        room.jury_pool = jurors;
    }

    /// Add vote to room (called by jury module)
    public(friend) fun add_vote(
        room_id: u64,
        juror: address,
        score_commit: vector<u8>,
    ) acquires RoomRegistry, Room {
        let registry = borrow_global<RoomRegistry>(@aptosroom);
        let room_owner = *table::borrow(&registry.rooms, room_id);
        let room = borrow_global_mut<Room>(room_owner);

        let vote = Vote {
            juror,
            score_commit,
            revealed: false,
            revealed_score: option::none<u64>(),
            revealed_salt: option::none<vector<u8>>(),
            committed_at: timestamp::now_seconds(),
            variance_flagged: false,
        };

        table::add(&mut room.votes, juror, vote);
    }

    /// Check if juror has committed
    public fun has_committed(room_id: u64, juror: address): bool acquires RoomRegistry, Room {
        let registry = borrow_global<RoomRegistry>(@aptosroom);
        let room_owner = *table::borrow(&registry.rooms, room_id);
        let room = borrow_global<Room>(room_owner);
        table::contains(&room.votes, juror)
    }

    /// Get vote commit hash
    public fun get_vote_commit(room_id: u64, juror: address): vector<u8> acquires RoomRegistry, Room {
        let registry = borrow_global<RoomRegistry>(@aptosroom);
        let room_owner = *table::borrow(&registry.rooms, room_id);
        let room = borrow_global<Room>(room_owner);
        let vote = table::borrow(&room.votes, juror);
        vote.score_commit
    }

    /// Check if juror has revealed
    public fun has_revealed(room_id: u64, juror: address): bool acquires RoomRegistry, Room {
        let registry = borrow_global<RoomRegistry>(@aptosroom);
        let room_owner = *table::borrow(&registry.rooms, room_id);
        let room = borrow_global<Room>(room_owner);
        if (!table::contains(&room.votes, juror)) {
            return false
        };
        let vote = table::borrow(&room.votes, juror);
        vote.revealed
    }

    /// Update vote as revealed (called by jury module)
    public(friend) fun mark_vote_revealed(
        room_id: u64,
        juror: address,
        score: u64,
        salt: vector<u8>,
    ) acquires RoomRegistry, Room {
        let registry = borrow_global<RoomRegistry>(@aptosroom);
        let room_owner = *table::borrow(&registry.rooms, room_id);
        let room = borrow_global_mut<Room>(room_owner);
        let vote = table::borrow_mut(&mut room.votes, juror);

        vote.revealed = true;
        vote.revealed_score = option::some(score);
        vote.revealed_salt = option::some(salt);
    }

    /// Set variance flag on vote (called by variance module)
    public(friend) fun flag_vote_for_variance(room_id: u64, juror: address) acquires RoomRegistry, Room {
        let registry = borrow_global<RoomRegistry>(@aptosroom);
        let room_owner = *table::borrow(&registry.rooms, room_id);
        let room = borrow_global_mut<Room>(room_owner);
        let vote = table::borrow_mut(&mut room.votes, juror);
        vote.variance_flagged = true;
    }

    /// Set jury score (called by aggregation module)
    public(friend) fun set_jury_score(room_id: u64, score: u64) acquires RoomRegistry, Room {
        let registry = borrow_global<RoomRegistry>(@aptosroom);
        let room_owner = *table::borrow(&registry.rooms, room_id);
        let room = borrow_global_mut<Room>(room_owner);
        room.jury_score = score;
        room.jury_score_computed = true;
    }

    /// Set final score for contributor (called by aggregation module)
    public(friend) fun set_final_score(room_id: u64, contributor: address, score: u64) acquires RoomRegistry, Room {
        let registry = borrow_global<RoomRegistry>(@aptosroom);
        let room_owner = *table::borrow(&registry.rooms, room_id);
        let room = borrow_global_mut<Room>(room_owner);
        table::upsert(&mut room.final_scores, contributor, score);
    }

    /// Mark client approved (called by settlement module)
    public(friend) fun set_client_approved(room_id: u64) acquires RoomRegistry, Room {
        let registry = borrow_global<RoomRegistry>(@aptosroom);
        let room_owner = *table::borrow(&registry.rooms, room_id);
        let room = borrow_global_mut<Room>(room_owner);
        room.client_approved = true;
    }

    /// Set winner and transition to settled (called by settlement module)
    public(friend) fun complete_settlement(room_id: u64, winner: address) acquires RoomRegistry, Room {
        let registry = borrow_global<RoomRegistry>(@aptosroom);
        let room_owner = *table::borrow(&registry.rooms, room_id);
        let room = borrow_global_mut<Room>(room_owner);

        let from_state = room.state;
        let to_state = constants::STATE_SETTLED();

        room.winner = option::some(winner);
        room.state = to_state;

        // Emit state change event
        event::emit(RoomStateChanged {
            room_id,
            from_state,
            to_state,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Get revealed scores (for variance/aggregation)
    public fun get_revealed_scores(room_id: u64): vector<u64> acquires RoomRegistry, Room {
        let registry = borrow_global<RoomRegistry>(@aptosroom);
        let room_owner = *table::borrow(&registry.rooms, room_id);
        let room = borrow_global<Room>(room_owner);

        let scores = vector::empty<u64>();
        let i = 0;
        let len = vector::length(&room.jury_pool);
        while (i < len) {
            let juror = *vector::borrow(&room.jury_pool, i);
            if (table::contains(&room.votes, juror)) {
                let vote = table::borrow(&room.votes, juror);
                if (vote.revealed && !vote.variance_flagged) {
                    let score = option::borrow(&vote.revealed_score);
                    vector::push_back(&mut scores, *score);
                };
            };
            i = i + 1;
        };
        scores
    }

    /// Get task reward for room
    public fun get_task_reward(room_id: u64): u64 acquires RoomRegistry, Room {
        let registry = borrow_global<RoomRegistry>(@aptosroom);
        let room_owner = *table::borrow(&registry.rooms, room_id);
        let room = borrow_global<Room>(room_owner);
        room.task_reward
    }

    // ============================================================
    // TEST-ONLY FUNCTIONS
    // ============================================================

    #[test_only]
    /// Initialize module for testing
    public fun init_for_test(account: &signer) {
        init_module(account);
    }

    #[test_only]
    /// Test helper to set jury pool
    public fun test_set_jury_pool(room_id: u64, jurors: vector<address>) acquires RoomRegistry, Room {
        set_jury_pool(room_id, jurors);
    }

    #[test_only]
    /// Test helper to add vote
    public fun test_add_vote(
        room_id: u64,
        juror: address,
        score_commit: vector<u8>,
    ) acquires RoomRegistry, Room {
        add_vote(room_id, juror, score_commit);
    }

    #[test_only]
    /// Test helper to mark vote revealed
    public fun test_mark_vote_revealed(
        room_id: u64,
        juror: address,
        score: u64,
        salt: vector<u8>,
    ) acquires RoomRegistry, Room {
        mark_vote_revealed(room_id, juror, score, salt);
    }

    #[test_only]
    /// Test helper to flag vote for variance
    public fun test_flag_vote_for_variance(room_id: u64, juror: address) acquires RoomRegistry, Room {
        flag_vote_for_variance(room_id, juror);
    }

    #[test_only]
    /// Test helper to set jury score
    public fun test_set_jury_score(room_id: u64, score: u64) acquires RoomRegistry, Room {
        set_jury_score(room_id, score);
    }

    #[test_only]
    /// Test helper to set final score
    public fun test_set_final_score(room_id: u64, contributor: address, score: u64) acquires RoomRegistry, Room {
        set_final_score(room_id, contributor, score);
    }

    #[test_only]
    /// Test helper to set client approved
    public fun test_set_client_approved(room_id: u64) acquires RoomRegistry, Room {
        set_client_approved(room_id);
    }

    #[test_only]
    /// Test helper to complete settlement
    public fun test_complete_settlement(room_id: u64, winner: address) acquires RoomRegistry, Room {
        complete_settlement(room_id, winner);
    }
}
