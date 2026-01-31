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
    use aptos_framework::coin::Coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use aptosroom::errors;
    use aptosroom::constants;
    use aptosroom::keycard;

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

    // ============================================================
    // PUBLIC ENTRY FUNCTIONS
    // ============================================================

    /// Create a new room
    /// Requires: caller has keycard, provides sufficient escrow
    // TODO: Implement create_room(
    //   account: &signer,
    //   category: String,
    //   task_hash: vector<u8>,
    //   task_reward: u64,
    //   deposit: Coin<AptosCoin>,
    //   deadline_submit: u64,
    //   deadline_jury_commit: u64,
    //   deadline_jury_reveal: u64,
    // )
    // Steps:
    // 1. Assert caller has keycard (E_NO_KEYCARD)
    // 2. Get next room ID from registry
    // 3. Create vault with deposit
    // 4. Create Room struct with state = STATE_INIT
    // 5. Store room
    // 6. Add to registry
    // 7. Emit RoomCreated event

    /// Open room for submissions (INIT -> OPEN)
    // TODO: Implement open_room(account: &signer, room_id: u64)
    // Steps:
    // 1. Assert caller is client (E_NOT_CLIENT)
    // 2. Assert valid transition (E_INVALID_STATE_TRANSITION)
    // 3. Update state
    // 4. Emit RoomStateChanged event

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
    public fun get_state(_room_id: u64): u8 {
        // TODO: Implement - fetch room and return state
        0
    }

    #[view]
    /// Get room client
    public fun get_client(_room_id: u64): address {
        // TODO: Implement - fetch room and return client
        @0x0
    }

    #[view]
    /// Check if contributor has submitted
    public fun has_submitted(_room_id: u64, _contributor: address): bool {
        // TODO: Implement - check submissions table
        false
    }

    #[view]
    /// Get submission count
    public fun get_submission_count(_room_id: u64): u64 {
        // TODO: Implement - return contributor_list length
        0
    }

    #[view]
    /// Get jury pool
    public fun get_jury_pool(_room_id: u64): vector<address> {
        // TODO: Implement - return room.jury_pool
        vector::empty<address>()
    }

    #[view]
    /// Check if room is settled
    public fun is_settled(_room_id: u64): bool {
        // TODO: Implement - check state == STATE_SETTLED
        false
    }

    // ============================================================
    // INTERNAL FUNCTIONS (for other modules)
    // ============================================================

    /// Set jury pool (called by jury module)
    // TODO: Implement set_jury_pool(room_id: u64, jurors: vector<address>)

    /// Add vote to room (called by jury module)
    // TODO: Implement add_vote(room_id: u64, vote: Vote)

    /// Update vote as revealed (called by jury module)
    // TODO: Implement mark_vote_revealed(
    //   room_id: u64,
    //   juror: address,
    //   score: u64,
    //   salt: vector<u8>,
    // )

    /// Set variance flag on vote (called by variance module)
    // TODO: Implement flag_vote_for_variance(room_id: u64, juror: address)

    /// Set jury score (called by aggregation module)
    // TODO: Implement set_jury_score(room_id: u64, score: u64)

    /// Set final score for contributor (called by aggregation module)
    // TODO: Implement set_final_score(room_id: u64, contributor: address, score: u64)

    /// Mark client approved (called by settlement module)
    // TODO: Implement set_client_approved(room_id: u64)

    /// Set winner and transition to settled (called by settlement module)
    // TODO: Implement complete_settlement(room_id: u64, winner: address)
}
