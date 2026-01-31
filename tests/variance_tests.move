/// ============================================================
/// TEST MODULE: Variance Tests
/// SPEC: TEST_PLAN.md Section 5.4
/// PURPOSE: Unit tests for variance detection algorithm
/// ============================================================
#[test_only]
module aptosroom::variance_tests {
    use std::vector;
    use aptos_framework::account;
    use aptosroom::variance;
    use aptosroom::constants;

    // ============================================================
    // OUTLIER DETECTION TESTS
    // ============================================================

    #[test]
    /// Test outlier is detected
    // Scores: [80, 82, 87, 15] → Juror D (score 15) is outlier
    // Nearest to 15 is 80, distance = 65 > 15 threshold
    fun test_outlier_detected() {
        let scores = vector[80, 82, 87, 15];
        
        // For juror with score 15:
        // - Distance to 80 = 65
        // - Distance to 82 = 67
        // - Distance to 87 = 72
        // Min distance = 65 > 15 → FLAGGED
        
        let min_dist = variance::test_find_min_distance(15, vector[80, 82, 87]);
        assert!(min_dist == 65, 0);
        assert!(min_dist > constants::VARIANCE_THRESHOLD(), 1);
    }

    #[test]
    /// Test consensus cluster is preserved (none flagged)
    // Scores: [80, 82, 84, 85, 87] → All within 7 points of neighbor
    fun test_consensus_cluster_preserved() {
        // For juror with score 80:
        // - Nearest = 82, distance = 2 ≤ 15 → NOT flagged
        let min_dist_80 = variance::test_find_min_distance(80, vector[82, 84, 85, 87]);
        assert!(min_dist_80 == 2, 0);
        assert!(min_dist_80 <= constants::VARIANCE_THRESHOLD(), 1);

        // For juror with score 87:
        // - Nearest = 85, distance = 2 ≤ 15 → NOT flagged
        let min_dist_87 = variance::test_find_min_distance(87, vector[80, 82, 84, 85]);
        assert!(min_dist_87 == 2, 2);
        assert!(min_dist_87 <= constants::VARIANCE_THRESHOLD(), 3);
    }

    #[test]
    /// Test threshold boundary (exactly 15 apart) is NOT flagged
    // Scores: [80, 95] → Distance = 15
    // Condition is > 15, not >= 15, so NOT flagged
    fun test_threshold_boundary_not_flagged() {
        let min_dist = variance::test_find_min_distance(80, vector[95]);
        assert!(min_dist == 15, 0);
        // 15 > 15 is false
        assert!(!(min_dist > constants::VARIANCE_THRESHOLD()), 1);
    }

    #[test]
    /// Test threshold boundary (16 apart) IS flagged
    // Scores: [80, 96] → Distance = 16 > 15 → FLAGGED
    fun test_threshold_boundary_flagged() {
        let min_dist = variance::test_find_min_distance(80, vector[96]);
        assert!(min_dist == 16, 0);
        assert!(min_dist > constants::VARIANCE_THRESHOLD(), 1);
    }

    #[test]
    /// Test multiple outliers
    // Scores: [10, 50, 90]
    // - 10: nearest = 50, distance = 40 > 15 → FLAGGED
    // - 50: nearest = 10 or 90, distance = 40 > 15 → FLAGGED
    // - 90: nearest = 50, distance = 40 > 15 → FLAGGED
    fun test_multiple_outliers() {
        let min_dist_10 = variance::test_find_min_distance(10, vector[50, 90]);
        let min_dist_50 = variance::test_find_min_distance(50, vector[10, 90]);
        let min_dist_90 = variance::test_find_min_distance(90, vector[10, 50]);
        
        assert!(min_dist_10 == 40, 0);
        assert!(min_dist_50 == 40, 1);
        assert!(min_dist_90 == 40, 2);
        
        // All are flagged
        assert!(min_dist_10 > constants::VARIANCE_THRESHOLD(), 3);
        assert!(min_dist_50 > constants::VARIANCE_THRESHOLD(), 4);
        assert!(min_dist_90 > constants::VARIANCE_THRESHOLD(), 5);
    }

    #[test]
    /// Test two scores very close
    // Scores: [80, 82] → Distance = 2 ≤ 15 → NOT flagged
    fun test_two_scores_close() {
        let min_dist = variance::test_find_min_distance(80, vector[82]);
        assert!(min_dist == 2, 0);
        assert!(min_dist <= constants::VARIANCE_THRESHOLD(), 1);
    }

    #[test]
    /// Test two scores very far
    // Scores: [20, 80] → Distance = 60 > 15 → Both flagged
    fun test_two_scores_far() {
        let min_dist_20 = variance::test_find_min_distance(20, vector[80]);
        let min_dist_80 = variance::test_find_min_distance(80, vector[20]);
        
        assert!(min_dist_20 == 60, 0);
        assert!(min_dist_80 == 60, 1);
        
        assert!(min_dist_20 > constants::VARIANCE_THRESHOLD(), 2);
        assert!(min_dist_80 > constants::VARIANCE_THRESHOLD(), 3);
    }

    #[test]
    /// Test identical scores (distance = 0)
    // Scores: [85, 85, 85] → All have distance 0 → NOT flagged
    fun test_identical_scores() {
        let min_dist = variance::test_find_min_distance(85, vector[85, 85]);
        assert!(min_dist == 0, 0);
        assert!(min_dist <= constants::VARIANCE_THRESHOLD(), 1);
    }

    // ============================================================
    // KEYCARD INTEGRATION TESTS
    // ============================================================

    #[test(framework = @0x1)]
    /// Test variance flag increments keycard
    // TODO: Implement test_variance_flag_increments_keycard
    // Steps:
    // 1. Create room with votes
    // 2. One juror is outlier
    // 3. Run variance detection
    // 4. Assert keycard.variance_flags == 1
    fun test_variance_flag_increments_keycard(framework: &signer) {
        // TODO: Implement
    }

    #[test(framework = @0x1)]
    /// Test valid vote keycard not incremented
    // TODO: Implement test_valid_vote_no_keycard_increment
    fun test_valid_vote_no_keycard_increment(framework: &signer) {
        // TODO: Implement
    }

    // ============================================================
    // EDGE CASES
    // ============================================================

    #[test]
    /// Test single vote (no neighbors to compare)
    // Single vote should not be flagged (no reference point)
    // TODO: Implement test_single_vote_not_flagged
    fun test_single_vote_not_flagged() {
        // With only one vote, there's no neighbor to compare
        // Implementation should handle this edge case
        // Expected: NOT flagged (or special handling)
        // TODO: Implement
    }

    #[test]
    /// Test max possible distance (0 vs 100)
    // Scores: [0, 100] → Distance = 100 > 15 → Both flagged
    fun test_max_distance() {
        let min_dist_0 = variance::test_find_min_distance(0, vector[100]);
        let min_dist_100 = variance::test_find_min_distance(100, vector[0]);
        
        assert!(min_dist_0 == 100, 0);
        assert!(min_dist_100 == 100, 1);
    }
}
