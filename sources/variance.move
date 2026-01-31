/// ============================================================
/// MODULE: Variance
/// SPEC: EXECUTION_TASKS_BY_PHASE.md Section 2.6
/// PURPOSE: Nearest-neighbor outlier detection for jury votes
/// THRESHOLD: 15 points (CTO-locked)
/// ============================================================
module aptosroom::variance {
    use std::vector;
    use std::option::{Self, Option};
    use aptos_std::table::{Self, Table};
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use aptosroom::errors;
    use aptosroom::constants;

    // ============================================================
    // EVENTS
    // ============================================================

    #[event]
    struct VarianceFlagged has drop, store {
        room_id: u64,
        juror: address,
        score: u64,
        min_distance: u64,
        timestamp: u64,
    }

    // ============================================================
    // VARIANCE DETECTION ALGORITHM
    // ============================================================

    /// Detect variance in jury votes using nearest-neighbor algorithm
    // TODO: Implement detect_variance(
    //   room_id: u64,
    //   scores: vector<(address, u64)>,  // (juror, revealed_score) pairs
    // ): vector<address>  // Returns list of flagged jurors
    //
    // Algorithm (Nearest-Neighbor Variance Detection):
    // 
    // For each juror j with score Sj:
    //   1. Calculate min_distance = minimum of |Sj - Si| for all i ≠ j
    //   2. If min_distance > VARIANCE_THRESHOLD (15):
    //      a. Flag juror j
    //      b. Emit VarianceFlagged event
    //      c. Increment keycard.variance_flags
    //   3. Else: juror j is not flagged
    //
    // Return: vector of flagged juror addresses
    //
    // Example:
    //   Scores: [80, 82, 87, 15]
    //   - Juror A (80): nearest = 82, distance = 2 → NOT flagged
    //   - Juror B (82): nearest = 80, distance = 2 → NOT flagged
    //   - Juror C (87): nearest = 82, distance = 5 → NOT flagged
    //   - Juror D (15): nearest = 80, distance = 65 → FLAGGED (65 > 15)

    /// Calculate minimum distance from a score to all other scores
    // TODO: Implement find_min_distance(
    //   target_score: u64,
    //   target_index: u64,
    //   all_scores: &vector<u64>,
    // ): u64
    //
    // Steps:
    // 1. Initialize min_dist = MAX_U64
    // 2. For each (index, score) in all_scores:
    //    a. If index == target_index: skip (don't compare to self)
    //    b. distance = abs_diff(target_score, score)
    //    c. If distance < min_dist: min_dist = distance
    // 3. Return min_dist

    /// Absolute difference between two u64 values
    // TODO: Implement abs_diff(a: u64, b: u64): u64
    //
    // Steps:
    // 1. If a >= b: return a - b
    // 2. Else: return b - a

    /// Check if a score is an outlier given other scores
    // TODO: Implement is_outlier(
    //   score: u64,
    //   other_scores: &vector<u64>,
    // ): bool
    //
    // Steps:
    // 1. Find minimum distance to any other score
    // 2. Return min_distance > VARIANCE_THRESHOLD

    // ============================================================
    // BATCH PROCESSING
    // ============================================================

    /// Process all votes and return flagged jurors
    // TODO: Implement process_room_variance(
    //   room_id: u64,
    // ): vector<address>
    //
    // Steps:
    // 1. Get all revealed scores from room
    // 2. Call detect_variance with scores
    // 3. For each flagged juror:
    //    a. Mark vote as variance_flagged in room
    //    b. Increment keycard variance_flags
    // 4. Return flagged juror addresses

    /// Get non-flagged scores (for aggregation)
    // TODO: Implement get_valid_scores(
    //   room_id: u64,
    // ): vector<u64>
    //
    // Steps:
    // 1. Get all revealed scores
    // 2. Filter out flagged votes
    // 3. Return only valid (non-flagged) scores

    // ============================================================
    // VIEW FUNCTIONS
    // ============================================================

    #[view]
    /// Check if a juror is flagged for variance in a room
    public fun is_flagged(_room_id: u64, _juror: address): bool {
        // TODO: Implement - check vote.variance_flagged
        false
    }

    #[view]
    /// Get count of flagged jurors in a room
    public fun get_flagged_count(_room_id: u64): u64 {
        // TODO: Implement - count flagged votes
        0
    }

    #[view]
    /// Get variance threshold constant
    public fun get_threshold(): u64 {
        constants::VARIANCE_THRESHOLD()
    }

    // ============================================================
    // TEST HELPERS
    // ============================================================

    #[test_only]
    /// Test helper: compute min distance for a score set
    public fun test_find_min_distance(
        target_score: u64,
        all_scores: vector<u64>,
    ): u64 {
        let min_dist: u64 = 18446744073709551615; // MAX_U64
        let len = vector::length(&all_scores);
        let i = 0;
        while (i < len) {
            let score = *vector::borrow(&all_scores, i);
            if (score != target_score) { // simplified for test
                let dist = if (target_score >= score) {
                    target_score - score
                } else {
                    score - target_score
                };
                if (dist < min_dist) {
                    min_dist = dist;
                };
            };
            i = i + 1;
        };
        min_dist
    }

    #[test]
    fun test_abs_diff_positive() {
        assert!(test_find_min_distance(80, vector[82, 85, 87]) == 2, 0);
    }

    #[test]
    fun test_outlier_detection() {
        // Score 15 with neighbors [80, 82, 87]
        // Nearest to 15 is 80, distance = 65
        let min_dist = test_find_min_distance(15, vector[80, 82, 87]);
        assert!(min_dist == 65, 0);
        assert!(min_dist > constants::VARIANCE_THRESHOLD(), 0);
    }

    #[test]
    fun test_consensus_not_flagged() {
        // Score 82 with neighbors [80, 84, 85, 87]
        // Nearest to 82 is 80 or 84, distance = 2
        let min_dist = test_find_min_distance(82, vector[80, 84, 85, 87]);
        assert!(min_dist == 2, 0);
        assert!(min_dist <= constants::VARIANCE_THRESHOLD(), 0);
    }

    #[test]
    fun test_threshold_boundary() {
        // Score 80 with neighbor [95]
        // Distance = 15 (exactly at threshold)
        // Should NOT be flagged (condition is > not >=)
        let min_dist = test_find_min_distance(80, vector[95]);
        assert!(min_dist == 15, 0);
        // 15 > 15 is false, so not flagged
        assert!(!(min_dist > constants::VARIANCE_THRESHOLD()), 0);
    }
}
