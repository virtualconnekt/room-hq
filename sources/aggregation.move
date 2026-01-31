/// ============================================================
/// MODULE: Aggregation
/// SPEC: EXECUTION_TASKS_BY_PHASE.md Section 2.7
/// PURPOSE: Median calculation for jury score
/// ROUNDING: Floor (CTO-locked)
/// ============================================================
module aptosroom::aggregation {
    use std::vector;
    use aptosroom::errors;
    use aptosroom::constants;

    // ============================================================
    // MEDIAN CALCULATION
    // ============================================================

    /// Calculate median of a score set
    // TODO: Implement calculate_median(scores: vector<u64>): u64
    //
    // Algorithm:
    // 1. If scores is empty: return 0 (triggers zero-vote path)
    // 2. Sort scores ascending
    // 3. Let n = length of scores
    // 4. If n is odd:
    //    - Return scores[n / 2]
    // 5. If n is even:
    //    - mid1 = scores[(n / 2) - 1]
    //    - mid2 = scores[n / 2]
    //    - Return floor((mid1 + mid2) / 2)
    //
    // Example (odd):
    //   Scores: [80, 82, 85, 87, 90] → median = 85
    //
    // Example (even):
    //   Scores: [80, 82, 87, 90] → median = floor((82 + 87) / 2) = 84

    /// Sort vector in ascending order (simple insertion sort)
    // TODO: Implement sort_ascending(scores: &mut vector<u64>)
    //
    // Steps (insertion sort):
    // 1. For i from 1 to len-1:
    //    a. key = scores[i]
    //    b. j = i - 1
    //    c. While j >= 0 && scores[j] > key:
    //       - scores[j + 1] = scores[j]
    //       - j = j - 1
    //    d. scores[j + 1] = key

    // ============================================================
    // JURY SCORE CALCULATION
    // ============================================================

    /// Calculate jury score from room votes
    // TODO: Implement calculate_jury_score(
    //   room_id: u64,
    //   valid_scores: vector<u64>,  // Non-flagged revealed scores
    // ): u64
    //
    // Steps:
    // 1. If empty: return 0 (zero-vote case)
    // 2. Calculate median of valid_scores
    // 3. Return median

    // ============================================================
    // FINAL SCORE CALCULATION
    // ============================================================

    /// Calculate final score using Dual-Key weights
    // TODO: Implement calculate_final_score(
    //   client_score: u64,
    //   jury_score: u64,
    // ): u64
    //
    // Formula:
    //   final_score = (client_score * CLIENT_WEIGHT + jury_score * JURY_WEIGHT) 
    //                 / WEIGHT_DENOMINATOR
    //
    // With CLIENT_WEIGHT = 60, JURY_WEIGHT = 40, DENOMINATOR = 100:
    //   final_score = (client_score * 60 + jury_score * 40) / 100
    //
    // Example:
    //   client_score = 90, jury_score = 80
    //   final = (90 * 60 + 80 * 40) / 100 = (5400 + 3200) / 100 = 86

    /// Process all submissions and calculate final scores
    // TODO: Implement process_final_scores(
    //   room_id: u64,
    //   jury_score: u64,
    // )
    //
    // Steps:
    // 1. For each submission in room:
    //    a. Get client_score (or 0 if not set)
    //    b. Calculate final_score
    //    c. Store final_score in room.final_scores

    // ============================================================
    // ZERO VOTES HANDLING
    // ============================================================

    /// Handle case when all votes are flagged
    // TODO: Implement handle_zero_valid_votes(
    //   room_id: u64,
    // ): bool  // Returns true if this is a zero-vote case
    //
    // CTO RULE (Zero Valid Votes):
    // 1. Refund escrow to client (100%)
    // 2. Keycards remain UNCHANGED
    // 3. Transition directly FINALIZED → SETTLED
    // 4. Emit RoomZeroVotesRefunded event
    //
    // Steps:
    // 1. Check if valid_scores count == 0
    // 2. If yes:
    //    a. Call vault::refund_to_client(room_id)
    //    b. Set room state to SETTLED
    //    c. Return true
    // 3. Return false

    // ============================================================
    // VIEW FUNCTIONS
    // ============================================================

    #[view]
    /// Get calculated jury score for a room
    // TODO: Implement get_jury_score(room_id: u64): u64

    #[view]
    /// Get final score for a contributor
    // TODO: Implement get_final_score(room_id: u64, contributor: address): u64

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
    use std::vector;

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
