/// ============================================================
/// MODULE: Aggregation
/// SPEC: EXECUTION_TASKS_BY_PHASE.md Section 2.7
/// PURPOSE: Median calculation for jury score
///          + Per-contributor tier aggregation (majority vote)
/// ROUNDING: Floor (CTO-locked)
/// ============================================================
module aptosroom::aggregation {
    use std::vector;
    use std::option;
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use aptosroom::constants;
    use aptosroom::room;
    use aptosroom::vault;

    // ============================================================
    // EVENTS
    // ============================================================

    #[event]
    struct JuryScoreComputed has drop, store {
        room_id: u64,
        jury_score: u64,
        valid_vote_count: u64,
        timestamp: u64,
    }

    #[event]
    struct FinalScoreComputed has drop, store {
        room_id: u64,
        contributor: address,
        client_score: u64,
        jury_score: u64,
        final_score: u64,
        timestamp: u64,
    }

    #[event]
    struct RoomZeroVotesRefunded has drop, store {
        room_id: u64,
        timestamp: u64,
    }

    #[event]
    struct ContributorTierComputed has drop, store {
        room_id: u64,
        contributor: address,
        final_tier: u8,
        tier_a_votes: u64,
        tier_b_votes: u64,
        tier_c_votes: u64,
        jury_score: u64,
        timestamp: u64,
    }

    #[event]
    struct TierAggregationComplete has drop, store {
        room_id: u64,
        contributor_count: u64,
        timestamp: u64,
    }

    // ============================================================
    // MEDIAN CALCULATION
    // ============================================================

    /// Calculate median of a score set
    public fun calculate_median(scores: vector<u64>): u64 {
        let len = vector::length(&scores);
        
        // If empty: return 0 (triggers zero-vote path)
        if (len == 0) {
            return 0
        };

        // Sort scores ascending
        let sorted = sort_ascending(scores);

        // Calculate median
        if (len % 2 == 1) {
            // Odd: return middle element
            *vector::borrow(&sorted, len / 2)
        } else {
            // Even: average of middle two (floor)
            let mid1 = *vector::borrow(&sorted, (len / 2) - 1);
            let mid2 = *vector::borrow(&sorted, len / 2);
            (mid1 + mid2) / 2
        }
    }

    /// Sort vector in ascending order (simple bubble sort for small arrays)
    public fun sort_ascending(scores: vector<u64>): vector<u64> {
        let len = vector::length(&scores);
        if (len <= 1) {
            return scores
        };

        let sorted = scores;
        let i = 0;
        while (i < len) {
            let j = 0;
            while (j < len - 1 - i) {
                let a = *vector::borrow(&sorted, j);
                let b = *vector::borrow(&sorted, j + 1);
                if (a > b) {
                    // Swap
                    *vector::borrow_mut(&mut sorted, j) = b;
                    *vector::borrow_mut(&mut sorted, j + 1) = a;
                };
                j = j + 1;
            };
            i = i + 1;
        };

        sorted
    }

    // ============================================================
    // JURY SCORE CALCULATION
    // ============================================================

    /// Calculate jury score from room votes
    public fun calculate_jury_score(
        room_id: u64,
        valid_scores: vector<u64>,
    ): u64 {
        let len = vector::length(&valid_scores);
        
        // If empty: return 0 (zero-vote case)
        if (len == 0) {
            return 0
        };

        // Calculate median of valid_scores
        let median = calculate_median(valid_scores);

        // Store jury score in room
        room::set_jury_score(room_id, median);

        // Emit event
        event::emit(JuryScoreComputed {
            room_id,
            jury_score: median,
            valid_vote_count: len,
            timestamp: timestamp::now_seconds(),
        });

        median
    }

    // ============================================================
    // FINAL SCORE CALCULATION
    // ============================================================

    /// Calculate final score using Dual-Key weights
    public fun calculate_final_score(
        client_score: u64,
        jury_score: u64,
    ): u64 {
        let client_weight = constants::CLIENT_WEIGHT();
        let jury_weight = constants::JURY_WEIGHT();
        let denominator = constants::WEIGHT_DENOMINATOR();

        // final_score = (client_score * 60 + jury_score * 40) / 100
        (client_score * client_weight + jury_score * jury_weight) / denominator
    }

    /// Process all submissions and calculate final scores
    public fun process_final_scores(room_id: u64, jury_score: u64) {
        let contributors = room::get_contributor_list(room_id);
        let len = vector::length(&contributors);

        let i = 0;
        while (i < len) {
            let contributor = *vector::borrow(&contributors, i);
            
            // Get client_score (or 0 if not set)
            let client_score_opt = room::get_client_score(room_id, contributor);
            let client_score = if (option::is_some(&client_score_opt)) {
                *option::borrow(&client_score_opt)
            } else {
                0
            };

            // Calculate final score
            let final_score = calculate_final_score(client_score, jury_score);

            // Store final score in room
            room::set_final_score(room_id, contributor, final_score);

            // Emit event
            event::emit(FinalScoreComputed {
                room_id,
                contributor,
                client_score,
                jury_score,
                final_score,
                timestamp: timestamp::now_seconds(),
            });

            i = i + 1;
        };
    }

    // ============================================================
    // TIER-BASED AGGREGATION (Per-Contributor)
    // ============================================================

    /// Aggregate tier votes for all contributors in a room
    /// Uses majority vote: count A/B/C votes, pick the tier with most votes
    /// Ties favor higher tier (A > B > C)
    public fun aggregate_tier_votes(room_id: u64) {
        let jury_pool = room::get_jury_pool(room_id);
        let contributors = room::get_contributor_list(room_id);

        // Build list of jurors who revealed tier votes
        let revealed_jurors = vector::empty<address>();
        let pool_len = vector::length(&jury_pool);
        let i = 0;
        while (i < pool_len) {
            let juror = *vector::borrow(&jury_pool, i);
            if (room::has_revealed_tier_vote(room_id, juror)) {
                vector::push_back(&mut revealed_jurors, juror);
            };
            i = i + 1;
        };

        let juror_count = vector::length(&revealed_jurors);
        
        // Process each contributor
        let contrib_len = vector::length(&contributors);
        let c = 0;
        while (c < contrib_len) {
            let contributor = *vector::borrow(&contributors, c);
            
            // Count tier votes for this contributor
            let (tier_a_votes, tier_b_votes, tier_c_votes) = count_tier_votes(
                room_id,
                contributor,
                &revealed_jurors
            );

            // Determine final tier by majority (ties favor higher tier)
            let final_tier = determine_majority_tier(tier_a_votes, tier_b_votes, tier_c_votes);
            
            // Convert tier to score
            let jury_score = constants::tier_to_score(final_tier);

            // Store tier and jury score for this contributor
            room::set_contributor_tier(room_id, contributor, final_tier);
            room::set_contributor_jury_score(room_id, contributor, jury_score);

            // Emit event
            event::emit(ContributorTierComputed {
                room_id,
                contributor,
                final_tier,
                tier_a_votes,
                tier_b_votes,
                tier_c_votes,
                jury_score,
                timestamp: timestamp::now_seconds(),
            });

            c = c + 1;
        };

        // Mark tiers as computed
        room::mark_tiers_computed(room_id);

        // Emit completion event
        event::emit(TierAggregationComplete {
            room_id,
            contributor_count: contrib_len,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Count tier votes for a specific contributor from all revealed jurors
    /// Returns (tier_a_count, tier_b_count, tier_c_count)
    fun count_tier_votes(
        room_id: u64,
        contributor: address,
        revealed_jurors: &vector<address>,
    ): (u64, u64, u64) {
        let tier_a = constants::TIER_A();
        let tier_b = constants::TIER_B();
        
        let count_a: u64 = 0;
        let count_b: u64 = 0;
        let count_c: u64 = 0;

        let len = vector::length(revealed_jurors);
        let j = 0;
        while (j < len) {
            let juror = *vector::borrow(revealed_jurors, j);
            let tier = get_tier_for_contributor(room_id, juror, contributor);
            
            if (tier == tier_a) {
                count_a = count_a + 1;
            } else if (tier == tier_b) {
                count_b = count_b + 1;
            } else {
                count_c = count_c + 1;
            };
            j = j + 1;
        };

        (count_a, count_b, count_c)
    }

    /// Get tier assigned by juror to contributor
    /// Based on juror's tier_a and tier_b selections
    fun get_tier_for_contributor(room_id: u64, juror: address, contributor: address): u8 {
        let tier_a_selections = room::get_juror_tier_a_selections(room_id, juror);
        let tier_b_selections = room::get_juror_tier_b_selections(room_id, juror);
        
        // Check if contributor is in tier A selections
        if (vector_contains(&tier_a_selections, contributor)) {
            return constants::TIER_A()
        };
        
        // Check if contributor is in tier B selections
        if (vector_contains(&tier_b_selections, contributor)) {
            return constants::TIER_B()
        };
        
        // Default to tier C
        constants::TIER_C()
    }

    /// Check if vector contains an address
    fun vector_contains(v: &vector<address>, target: address): bool {
        let len = vector::length(v);
        let i = 0;
        while (i < len) {
            if (*vector::borrow(v, i) == target) {
                return true
            };
            i = i + 1;
        };
        false
    }

    /// Determine majority tier from vote counts
    /// Ties favor higher tier (A > B > C)
    public fun determine_majority_tier(tier_a_votes: u64, tier_b_votes: u64, tier_c_votes: u64): u8 {
        if (tier_a_votes >= tier_b_votes && tier_a_votes >= tier_c_votes) {
            constants::TIER_A()
        } else if (tier_b_votes >= tier_c_votes) {
            constants::TIER_B()
        } else {
            constants::TIER_C()
        }
    }

    /// Process final scores using per-contributor tier-based jury scores
    /// Uses the new formula: final = (0.6 * client_score) + tier_score
    public fun process_tier_final_scores(room_id: u64) {
        let contributors = room::get_contributor_list(room_id);
        let len = vector::length(&contributors);

        let i = 0;
        while (i < len) {
            let contributor = *vector::borrow(&contributors, i);
            
            // Get client_score (or 0 if not set)
            let client_score_opt = room::get_client_score(room_id, contributor);
            let client_score = if (option::is_some(&client_score_opt)) {
                *option::borrow(&client_score_opt)
            } else {
                0
            };

            // Get per-contributor jury score from tier
            let jury_score = room::get_contributor_jury_score(room_id, contributor);

            // Calculate final score using tier formula:
            // final = (client_score * 60 / 100) + jury_score
            // Which is: 60% of client score + tier-based jury score (40, 30, or 20)
            let final_score = calculate_tier_final_score(client_score, jury_score);

            // Store final score in room
            room::set_final_score(room_id, contributor, final_score);

            // Emit event
            event::emit(FinalScoreComputed {
                room_id,
                contributor,
                client_score,
                jury_score,
                final_score,
                timestamp: timestamp::now_seconds(),
            });

            i = i + 1;
        };
    }

    /// Calculate final score for tier-based system
    /// Formula: (client_score * 60 / 100) + tier_score
    /// tier_score is already the jury contribution (40, 30, or 20)
    public fun calculate_tier_final_score(client_score: u64, tier_jury_score: u64): u64 {
        let client_weight = constants::CLIENT_WEIGHT();
        let denominator = constants::WEIGHT_DENOMINATOR();
        
        // 60% of client score + tier jury score
        (client_score * client_weight / denominator) + tier_jury_score
    }

    // ============================================================
    // ZERO VOTES HANDLING
    // ============================================================

    /// Handle case when all votes are flagged
    /// CTO RULE: Refund escrow to client (100%), keycards unchanged
    public fun handle_zero_valid_votes(room_id: u64): bool {
        let valid_scores = room::get_revealed_scores(room_id);
        
        // Check if valid_scores count == 0
        if (vector::length(&valid_scores) == 0) {
            // Refund escrow to client
            vault::refund_to_client(room_id);

            // Emit event
            event::emit(RoomZeroVotesRefunded {
                room_id,
                timestamp: timestamp::now_seconds(),
            });

            return true
        };

        false
    }

    // ============================================================
    // VIEW FUNCTIONS
    // ============================================================

    #[view]
    /// Get calculated jury score for a room
    public fun get_jury_score(room_id: u64): u64 {
        room::get_jury_score(room_id)
    }

    #[view]
    /// Get final score for a contributor
    public fun get_final_score(room_id: u64, contributor: address): u64 {
        room::get_final_score(room_id, contributor)
    }

    #[view]
    /// Get per-contributor tier
    public fun get_contributor_tier(room_id: u64, contributor: address): u8 {
        room::get_contributor_tier(room_id, contributor)
    }

    #[view]
    /// Get per-contributor jury score from tier
    public fun get_contributor_jury_score(room_id: u64, contributor: address): u64 {
        room::get_contributor_jury_score(room_id, contributor)
    }

    #[view]
    /// Check if tiers have been computed for room
    public fun are_tiers_computed(room_id: u64): bool {
        room::are_tiers_computed(room_id)
    }

    // ============================================================
    // TESTS
    // ============================================================

    #[test]
    fun test_median_odd_count() {
        let scores = vector[80, 82, 85, 87, 90];
        // Sorted, median is middle element (index 2)
        // Expected: 85
        let expected = 85;
        let median = test_calculate_median(scores);
        assert!(median == expected, 0);
    }

    #[test]
    fun test_median_even_count() {
        let scores = vector[80, 82, 87, 90];
        // Sorted, median is average of indices 1 and 2
        // (82 + 87) / 2 = 84 (floor)
        let expected = 84;
        let median = test_calculate_median(scores);
        assert!(median == expected, 0);
    }

    #[test]
    fun test_median_single() {
        let scores = vector[75];
        let expected = 75;
        let median = test_calculate_median(scores);
        assert!(median == expected, 0);
    }

    #[test]
    fun test_median_empty() {
        let scores = vector::empty<u64>();
        let expected = 0;
        let median = test_calculate_median(scores);
        assert!(median == expected, 0);
    }

    #[test]
    fun test_final_score_calculation() {
        // client = 90, jury = 80
        // final = (90 * 60 + 80 * 40) / 100 = 86
        let final_score = test_calculate_final_score(90, 80);
        assert!(final_score == 86, 0);
    }

    #[test]
    fun test_final_score_equal_weights() {
        // client = 80, jury = 80
        // final = (80 * 60 + 80 * 40) / 100 = 80
        let final_score = test_calculate_final_score(80, 80);
        assert!(final_score == 80, 0);
    }

    // ============================================================
    // TEST HELPERS
    // ============================================================

    #[test_only]
    fun test_calculate_median(scores: vector<u64>): u64 {
        let len = vector::length(&scores);
        if (len == 0) {
            return 0
        };
        
        // Simple bubble sort for test
        let i = 0;
        while (i < len) {
            let j = 0;
            while (j < len - 1 - i) {
                let a = *vector::borrow(&scores, j);
                let b = *vector::borrow(&scores, j + 1);
                if (a > b) {
                    *vector::borrow_mut(&mut scores, j) = b;
                    *vector::borrow_mut(&mut scores, j + 1) = a;
                };
                j = j + 1;
            };
            i = i + 1;
        };
        
        if (len % 2 == 1) {
            // Odd: return middle
            *vector::borrow(&scores, len / 2)
        } else {
            // Even: average of middle two (floor)
            let mid1 = *vector::borrow(&scores, (len / 2) - 1);
            let mid2 = *vector::borrow(&scores, len / 2);
            (mid1 + mid2) / 2
        }
    }

    #[test_only]
    fun test_calculate_final_score(client_score: u64, jury_score: u64): u64 {
        let client_weight = constants::CLIENT_WEIGHT();
        let jury_weight = constants::JURY_WEIGHT();
        let denominator = constants::WEIGHT_DENOMINATOR();
        
        (client_score * client_weight + jury_score * jury_weight) / denominator
    }
}
