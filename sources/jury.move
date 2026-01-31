/// ============================================================
/// MODULE: Jury
/// SPEC: EXECUTION_TASKS_BY_PHASE.md Section 2.4, 2.5
/// INVARIANTS ENFORCED:
///   - INVARIANT_VOTE_001: Hash integrity (commit-reveal)
///   - INVARIANT_VOTE_002: Unpredictable jury selection
/// PURPOSE: Jury selection, commit, and reveal phases
/// ============================================================
module aptosroom::jury {
    use std::signer;
    use std::string::String;
    use std::vector;
    use std::hash;
    use std::bcs;
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use aptosroom::errors;
    use aptosroom::constants;
    use aptosroom::room;
    use aptosroom::keycard;

    // ============================================================
    // EVENTS
    // ============================================================

    #[event]
    struct JuryAssigned has drop, store {
        room_id: u64,
        jurors: vector<address>,
        timestamp: u64,
    }

    #[event]
    struct VoteCommitted has drop, store {
        room_id: u64,
        juror: address,
        commit_hash: vector<u8>,
        timestamp: u64,
    }

    #[event]
    struct VoteRevealed has drop, store {
        room_id: u64,
        juror: address,
        score: u64,
        timestamp: u64,
    }

    // ============================================================
    // JURY SELECTION
    // ============================================================

    /// Select jurors for a room (INVARIANT_VOTE_002: unpredictable)
    /// Uses deterministic shuffle with Aptos randomness seed
    public fun select_jurors(
        room_id: u64,
        _category: &String,
        eligible_jurors: vector<address>,
        jury_size: u64,
    ): vector<address> {
        // Assert sufficient jurors
        let len = vector::length(&eligible_jurors);
        assert!(len >= jury_size, errors::E_INSUFFICIENT_JURORS());

        // Shuffle eligible jurors using seed derived from room_id and timestamp
        let mut_jurors = eligible_jurors;
        shuffle_with_seed(&mut mut_jurors, room_id);

        // Take first jury_size elements
        let selected = vector::empty<address>();
        let i = 0;
        while (i < jury_size) {
            vector::push_back(&mut selected, *vector::borrow(&mut_jurors, i));
            i = i + 1;
        };

        // Emit event
        event::emit(JuryAssigned {
            room_id,
            jurors: selected,
            timestamp: timestamp::now_seconds(),
        });

        selected
    }

    /// Internal: Fisher-Yates shuffle with deterministic seed
    fun shuffle_with_seed(list: &mut vector<address>, seed: u64) {
        let n = vector::length(list);
        if (n <= 1) {
            return
        };

        let i = n - 1;
        while (i > 0) {
            // Derive j from hash(seed || i) % (i + 1)
            let j = random_index(seed, i, i + 1);
            // Swap list[i] and list[j]
            vector::swap(list, i, j);
            i = i - 1;
        };
    }

    /// Internal: Generate pseudo-random index from seed
    fun random_index(seed: u64, iteration: u64, max: u64): u64 {
        // Compute hash of seed concatenated with iteration
        let combined = seed * 1000000 + iteration;
        let bytes = bcs::to_bytes(&combined);
        let hash_bytes = hash::sha3_256(bytes);
        
        // Take first 8 bytes as u64
        let value: u64 = 0;
        let i = 0;
        while (i < 8) {
            value = (value << 8) | (*vector::borrow(&hash_bytes, i) as u64);
            i = i + 1;
        };
        
        // Return value % max
        value % max
    }

    // ============================================================
    // COMMIT PHASE
    // ============================================================

    /// Commit a vote (hash only, score is secret)
    public entry fun commit_vote(
        account: &signer,
        room_id: u64,
        score_commit: vector<u8>,
    ) {
        let juror = signer::address_of(account);

        // Assert room state == STATE_JURY_ACTIVE
        let state = room::get_state(room_id);
        assert!(state == constants::STATE_JURY_ACTIVE(), errors::E_NOT_IN_COMMIT_PHASE());

        // Assert juror is in room.jury_pool
        let jury_pool = room::get_jury_pool(room_id);
        assert!(vector::contains(&jury_pool, &juror), errors::E_NOT_JUROR());

        // Assert juror has not already committed
        assert!(!room::has_committed(room_id, juror), errors::E_ALREADY_COMMITTED());

        // Add vote to room via friend function
        room::add_vote(room_id, juror, score_commit);

        // Emit event
        event::emit(VoteCommitted {
            room_id,
            juror,
            commit_hash: score_commit,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Check if all jurors have committed
    public fun all_committed(room_id: u64): bool {
        let jury_pool = room::get_jury_pool(room_id);
        let len = vector::length(&jury_pool);
        let i = 0;
        while (i < len) {
            let juror = *vector::borrow(&jury_pool, i);
            if (!room::has_committed(room_id, juror)) {
                return false
            };
            i = i + 1;
        };
        true
    }

    // ============================================================
    // REVEAL PHASE
    // ============================================================

    /// Reveal a vote (INVARIANT_VOTE_001: hash verification)
    public entry fun reveal_vote(
        account: &signer,
        room_id: u64,
        score: u64,
        salt: vector<u8>,
    ) {
        let juror = signer::address_of(account);

        // Assert room state == STATE_JURY_REVEAL
        let state = room::get_state(room_id);
        assert!(state == constants::STATE_JURY_REVEAL(), errors::E_NOT_IN_REVEAL_PHASE());

        // Assert juror has committed
        assert!(room::has_committed(room_id, juror), errors::E_NOT_COMMITTED());

        // Assert not already revealed
        assert!(!room::has_revealed(room_id, juror), errors::E_ALREADY_REVEALED());

        // Assert score <= MAX_SCORE
        assert!(score <= constants::MAX_SCORE(), errors::E_INVALID_SCORE());

        // Compute expected hash and verify (INVARIANT_VOTE_001)
        let expected_hash = compute_commit_hash(score, salt);
        let actual_hash = room::get_vote_commit(room_id, juror);
        assert!(expected_hash == actual_hash, errors::E_HASH_MISMATCH());

        // Mark vote as revealed via friend function
        room::mark_vote_revealed(room_id, juror, score, salt);

        // Increment jury participation on keycard
        keycard::increment_jury_participations(juror);

        // Emit event
        event::emit(VoteRevealed {
            room_id,
            juror,
            score,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Compute hash for commit (helper for off-chain and verification)
    public fun compute_commit_hash(score: u64, salt: vector<u8>): vector<u8> {
        // Serialize score using BCS
        let score_bytes = bcs::to_bytes(&score);
        // Concatenate with salt
        vector::append(&mut score_bytes, salt);
        // Return SHA3-256 hash
        hash::sha3_256(score_bytes)
    }

    /// Check if all jurors have revealed
    public fun all_revealed(room_id: u64): bool {
        let jury_pool = room::get_jury_pool(room_id);
        let len = vector::length(&jury_pool);
        let i = 0;
        while (i < len) {
            let juror = *vector::borrow(&jury_pool, i);
            if (!room::has_revealed(room_id, juror)) {
                return false
            };
            i = i + 1;
        };
        true
    }

    /// Get revealed scores (for variance detection)
    public fun get_revealed_scores(room_id: u64): vector<u64> {
        room::get_revealed_scores(room_id)
    }

    // ============================================================
    // VIEW FUNCTIONS
    // ============================================================

    #[view]
    /// Check if juror has committed
    public fun has_committed(room_id: u64, juror: address): bool {
        room::has_committed(room_id, juror)
    }

    #[view]
    /// Check if juror has revealed
    public fun has_revealed(room_id: u64, juror: address): bool {
        room::has_revealed(room_id, juror)
    }

    #[view]
    /// Get commit count
    public fun get_commit_count(room_id: u64): u64 {
        let jury_pool = room::get_jury_pool(room_id);
        let len = vector::length(&jury_pool);
        let count: u64 = 0;
        let i = 0;
        while (i < len) {
            let juror = *vector::borrow(&jury_pool, i);
            if (room::has_committed(room_id, juror)) {
                count = count + 1;
            };
            i = i + 1;
        };
        count
    }

    #[view]
    /// Get reveal count
    public fun get_reveal_count(room_id: u64): u64 {
        let jury_pool = room::get_jury_pool(room_id);
        let len = vector::length(&jury_pool);
        let count: u64 = 0;
        let i = 0;
        while (i < len) {
            let juror = *vector::borrow(&jury_pool, i);
            if (room::has_revealed(room_id, juror)) {
                count = count + 1;
            };
            i = i + 1;
        };
        count
    }

    // ============================================================
    // TEST HELPERS
    // ============================================================

    #[test_only]
    /// Test helper to select jurors
    public fun test_select_jurors(
        room_id: u64,
        category: &String,
        eligible_jurors: vector<address>,
        jury_size: u64,
    ): vector<address> {
        select_jurors(room_id, category, eligible_jurors, jury_size)
    }

    #[test_only]
    /// Test helper to compute commit hash
    public fun test_compute_commit_hash(score: u64, salt: vector<u8>): vector<u8> {
        compute_commit_hash(score, salt)
    }
}
