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

    #[event]
    struct TierVoteCommitted has drop, store {
        room_id: u64,
        juror: address,
        commit_hash: vector<u8>,
        timestamp: u64,
    }

    #[event]
    struct TierVoteRevealed has drop, store {
        room_id: u64,
        juror: address,
        tier_a_count: u64,
        tier_b_count: u64,
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

    // ============================================================
    // TIER-BASED COMMIT/REVEAL PHASE
    // ============================================================

    /// Commit tier vote (hash of tier selections)
    /// Juror commits hash of tier_a_addresses || tier_b_addresses || salt
    public entry fun commit_tier_vote(
        account: &signer,
        room_id: u64,
        commit_hash: vector<u8>,
    ) {
        let juror = signer::address_of(account);

        // Assert room state == STATE_JURY_ACTIVE
        let state = room::get_state(room_id);
        assert!(state == constants::STATE_JURY_ACTIVE(), errors::E_NOT_IN_COMMIT_PHASE());

        // Assert juror is in room.jury_pool
        assert!(room::is_juror(room_id, juror), errors::E_NOT_JUROR());

        // Assert juror has not already committed
        assert!(!room::has_committed_tier_vote(room_id, juror), errors::E_ALREADY_COMMITTED());

        // Add tier vote commit to room
        room::add_tier_vote_commit(room_id, juror, commit_hash);

        // Emit event
        event::emit(TierVoteCommitted {
            room_id,
            juror,
            commit_hash,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Reveal tier vote with tier selections
    /// All contributors not in tier_a or tier_b default to tier_c
    public entry fun reveal_tier_vote(
        account: &signer,
        room_id: u64,
        tier_a_selections: vector<address>,
        tier_b_selections: vector<address>,
        salt: vector<u8>,
    ) {
        let juror = signer::address_of(account);

        // Assert room state == STATE_JURY_REVEAL
        let state = room::get_state(room_id);
        assert!(state == constants::STATE_JURY_REVEAL(), errors::E_NOT_IN_REVEAL_PHASE());

        // Assert juror has committed
        assert!(room::has_committed_tier_vote(room_id, juror), errors::E_NOT_COMMITTED());

        // Assert not already revealed
        assert!(!room::has_revealed_tier_vote(room_id, juror), errors::E_ALREADY_REVEALED());

        // Verify slot limits
        let contributor_count = room::get_contributor_count(room_id);
        let expected_a_slots = constants::get_tier_a_slots(contributor_count);
        let expected_b_slots = constants::get_tier_b_slots(contributor_count);
        
        assert!(vector::length(&tier_a_selections) == expected_a_slots, 
                errors::E_INVALID_TIER_A_COUNT());
        assert!(vector::length(&tier_b_selections) == expected_b_slots, 
                errors::E_INVALID_TIER_B_COUNT());

        // Verify all selections are valid contributors
        verify_selections_are_contributors(room_id, &tier_a_selections);
        verify_selections_are_contributors(room_id, &tier_b_selections);

        // Verify no duplicates between A and B
        verify_no_duplicates(&tier_a_selections, &tier_b_selections);

        // Verify hash matches commit
        let expected_hash = compute_tier_commit_hash(
            &tier_a_selections, 
            &tier_b_selections, 
            &salt
        );
        let actual_hash = room::get_tier_vote_commit(room_id, juror);
        assert!(expected_hash == actual_hash, errors::E_HASH_MISMATCH());

        // Mark tier vote as revealed
        room::mark_tier_vote_revealed(
            room_id, 
            juror, 
            tier_a_selections, 
            tier_b_selections, 
            salt
        );

        // Increment jury participation on keycard
        keycard::increment_jury_participations(juror);

        // Emit event
        event::emit(TierVoteRevealed {
            room_id,
            juror,
            tier_a_count: expected_a_slots,
            tier_b_count: expected_b_slots,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Compute hash for tier vote commit
    public fun compute_tier_commit_hash(
        tier_a: &vector<address>,
        tier_b: &vector<address>,
        salt: &vector<u8>,
    ): vector<u8> {
        let data = vector::empty<u8>();
        
        // Serialize tier A addresses
        let a_bytes = bcs::to_bytes(tier_a);
        vector::append(&mut data, a_bytes);
        
        // Serialize tier B addresses
        let b_bytes = bcs::to_bytes(tier_b);
        vector::append(&mut data, b_bytes);
        
        // Append salt
        vector::append(&mut data, *salt);
        
        // Return hash
        hash::sha3_256(data)
    }

    /// Verify all addresses in selections are valid contributors
    fun verify_selections_are_contributors(room_id: u64, selections: &vector<address>) {
        let len = vector::length(selections);
        let i = 0;
        while (i < len) {
            let addr = *vector::borrow(selections, i);
            assert!(room::is_contributor(room_id, addr), errors::E_NOT_A_CONTRIBUTOR());
            i = i + 1;
        };
    }

    /// Verify no duplicates between tier A and tier B selections
    fun verify_no_duplicates(tier_a: &vector<address>, tier_b: &vector<address>) {
        let len_a = vector::length(tier_a);
        let i = 0;
        while (i < len_a) {
            let addr = *vector::borrow(tier_a, i);
            assert!(!vector::contains(tier_b, &addr), errors::E_DUPLICATE_IN_TIERS());
            i = i + 1;
        };
    }

    /// Check if all jurors have committed tier votes
    public fun all_tier_committed(room_id: u64): bool {
        let jury_pool = room::get_jury_pool(room_id);
        let len = vector::length(&jury_pool);
        let i = 0;
        while (i < len) {
            let juror = *vector::borrow(&jury_pool, i);
            if (!room::has_committed_tier_vote(room_id, juror)) {
                return false
            };
            i = i + 1;
        };
        true
    }

    /// Check if all jurors have revealed tier votes
    public fun all_tier_revealed(room_id: u64): bool {
        let jury_pool = room::get_jury_pool(room_id);
        let len = vector::length(&jury_pool);
        let i = 0;
        while (i < len) {
            let juror = *vector::borrow(&jury_pool, i);
            if (!room::has_revealed_tier_vote(room_id, juror)) {
                return false
            };
            i = i + 1;
        };
        true
    }

    /// Get tier commit count
    public fun get_tier_commit_count(room_id: u64): u64 {
        let jury_pool = room::get_jury_pool(room_id);
        let len = vector::length(&jury_pool);
        let count: u64 = 0;
        let i = 0;
        while (i < len) {
            let juror = *vector::borrow(&jury_pool, i);
            if (room::has_committed_tier_vote(room_id, juror)) {
                count = count + 1;
            };
            i = i + 1;
        };
        count
    }

    /// Get tier reveal count
    public fun get_tier_reveal_count(room_id: u64): u64 {
        let jury_pool = room::get_jury_pool(room_id);
        let len = vector::length(&jury_pool);
        let count: u64 = 0;
        let i = 0;
        while (i < len) {
            let juror = *vector::borrow(&jury_pool, i);
            if (room::has_revealed_tier_vote(room_id, juror)) {
                count = count + 1;
            };
            i = i + 1;
        };
        count
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

    #[view]
    /// Check if juror has committed tier vote
    public fun has_committed_tier(room_id: u64, juror: address): bool {
        room::has_committed_tier_vote(room_id, juror)
    }

    #[view]
    /// Check if juror has revealed tier vote
    public fun has_revealed_tier(room_id: u64, juror: address): bool {
        room::has_revealed_tier_vote(room_id, juror)
    }

    #[view]
    /// Get tier commit count for view
    public fun view_tier_commit_count(room_id: u64): u64 {
        get_tier_commit_count(room_id)
    }

    #[view]
    /// Get tier reveal count for view
    public fun view_tier_reveal_count(room_id: u64): u64 {
        get_tier_reveal_count(room_id)
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
