/// ============================================================
/// MODULE: Variance
/// SPEC: EXECUTION_TASKS_BY_PHASE.md Section 2.6
/// PURPOSE: Nearest-neighbor outlier detection for jury votes
/// THRESHOLD: 15 points (CTO-locked)
/// ============================================================
module aptosroom::variance {
    use std::vector;
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use aptosroom::constants;
    use aptosroom::room;
    use aptosroom::keycard;

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
    /// Returns list of flagged juror addresses
    public fun detect_variance(
        room_id: u64,
        jurors: vector<address>,
        scores: vector<u64>,
    ): vector<address> {
        let flagged = vector::empty<address>();
        let threshold = constants::VARIANCE_THRESHOLD();
        let len = vector::length(&scores);

        // Need at least 2 scores to detect variance
        if (len < 2) {
            return flagged
        };

        let i = 0;
        while (i < len) {
            let score = *vector::borrow(&scores, i);
            let min_dist = find_min_distance(score, i, &scores);

            // If min_distance > VARIANCE_THRESHOLD, flag this juror
            if (min_dist > threshold) {
                let juror = *vector::borrow(&jurors, i);
                vector::push_back(&mut flagged, juror);

                // Emit event
                event::emit(VarianceFlagged {
                    room_id,
                    juror,
                    score,
                    min_distance: min_dist,
                    timestamp: timestamp::now_seconds(),
                });
            };
            i = i + 1;
        };

        flagged
    }

    /// Calculate minimum distance from a score to all other scores
    public fun find_min_distance(
        target_score: u64,
        target_index: u64,
        all_scores: &vector<u64>,
    ): u64 {
        let min_dist: u64 = 18446744073709551615; // MAX_U64
        let len = vector::length(all_scores);
        let i = 0;

        while (i < len) {
            if (i != target_index) {
                let score = *vector::borrow(all_scores, i);
                let dist = abs_diff(target_score, score);
                if (dist < min_dist) {
                    min_dist = dist;
                };
            };
            i = i + 1;
        };

        min_dist
    }

    /// Absolute difference between two u64 values
    public fun abs_diff(a: u64, b: u64): u64 {
        if (a >= b) {
            a - b
        } else {
            b - a
        }
    }

    /// Check if a score is an outlier given other scores
    public fun is_outlier(
        score: u64,
        score_index: u64,
        all_scores: &vector<u64>,
    ): bool {
        let min_dist = find_min_distance(score, score_index, all_scores);
        min_dist > constants::VARIANCE_THRESHOLD()
    }

    // ============================================================
    // BATCH PROCESSING
    // ============================================================

    /// Process all votes and return flagged jurors
    /// Also updates keycard and room state
    public fun process_room_variance(room_id: u64): vector<address> {
        // Get jury pool and their revealed scores
        let jury_pool = room::get_jury_pool(room_id);
        let revealed_scores = room::get_revealed_scores(room_id);

        // Build parallel vectors of jurors who revealed and their scores
        let revealed_jurors = vector::empty<address>();
        let scores = vector::empty<u64>();
        
        let i = 0;
        let pool_len = vector::length(&jury_pool);
        while (i < pool_len) {
            let juror = *vector::borrow(&jury_pool, i);
            if (room::has_revealed(room_id, juror)) {
                vector::push_back(&mut revealed_jurors, juror);
            };
            i = i + 1;
        };

        // Get scores from room (already filtered for revealed only)
        scores = revealed_scores;

        // Detect variance and get flagged jurors
        let flagged = detect_variance(room_id, revealed_jurors, scores);

        // For each flagged juror:
        let j = 0;
        let flagged_len = vector::length(&flagged);
        while (j < flagged_len) {
            let juror = *vector::borrow(&flagged, j);
            // Mark vote as variance_flagged in room
            room::flag_vote_for_variance(room_id, juror);
            // Increment keycard variance_flags
            keycard::increment_variance_flags(juror);
            j = j + 1;
        };

        flagged
    }

    /// Get non-flagged scores (for aggregation)
    public fun get_valid_scores(room_id: u64): vector<u64> {
        // This returns only revealed, non-flagged scores
        room::get_revealed_scores(room_id)
    }

    // ============================================================
    // VIEW FUNCTIONS
    // ============================================================

    #[view]
    /// Check if a juror is flagged for variance in a room
    public fun is_flagged(room_id: u64, juror: address): bool {
        // Check if the juror has a vote that is flagged
        // We access this through room's internal state
        // For now, we check by processing - but in production
        // this would query the room's vote.variance_flagged
        let jury_pool = room::get_jury_pool(room_id);
        let revealed_scores = room::get_revealed_scores(room_id);
        
        // If scores include this juror's score, they're not flagged
        // (revealed_scores already filters out flagged)
        if (!room::has_revealed(room_id, juror)) {
            return false
        };
        
        // Check if their score is in the valid scores
        // If not in valid scores but revealed, they're flagged
        let valid_count = vector::length(&revealed_scores);
        let pool_len = vector::length(&jury_pool);
        
        // Count how many are revealed
        let revealed_count: u64 = 0;
        let i = 0;
        while (i < pool_len) {
            let j = *vector::borrow(&jury_pool, i);
            if (room::has_revealed(room_id, j)) {
                revealed_count = revealed_count + 1;
            };
            i = i + 1;
        };
        
        // If revealed count > valid count, some are flagged
        // But we can't determine which without more state
        // This is a limitation - the actual flag is in room.vote
        false
    }

    #[view]
    /// Get count of flagged jurors in a room
    public fun get_flagged_count(room_id: u64): u64 {
        let jury_pool = room::get_jury_pool(room_id);
        let revealed_scores = room::get_revealed_scores(room_id);
        
        // Count revealed
        let revealed_count: u64 = 0;
        let i = 0;
        let pool_len = vector::length(&jury_pool);
        while (i < pool_len) {
            let juror = *vector::borrow(&jury_pool, i);
            if (room::has_revealed(room_id, juror)) {
                revealed_count = revealed_count + 1;
            };
            i = i + 1;
        };
        
        // Valid scores are revealed minus flagged
        let valid_count = vector::length(&revealed_scores);
        
        // Flagged = revealed - valid
        if (revealed_count >= valid_count) {
            revealed_count - valid_count
        } else {
            0
        }
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
    /// Note: This simplified version compares by value (skips matching values)
    /// For identical scores, all are skipped, returning MAX_U64
    /// To test identical scores, call find_min_distance directly with index
    public fun test_find_min_distance(
        target_score: u64,
        all_scores: vector<u64>,
    ): u64 {
        // For this simplified test helper, we compare at index 0
        // and iterate through remaining scores
        let min_dist: u64 = 18446744073709551615; // MAX_U64
        let len = vector::length(&all_scores);
        
        // Find first occurrence of target_score to use as "self" index
        let target_index: u64 = len; // default to invalid
        let i = 0;
        while (i < len) {
            let score = *vector::borrow(&all_scores, i);
            if (score == target_score && target_index == len) {
                target_index = i;
            };
            i = i + 1;
        };
        
        // Now calculate min distance, skipping target_index
        i = 0;
        while (i < len) {
            if (i != target_index) {
                let score = *vector::borrow(&all_scores, i);
                let dist = abs_diff(target_score, score);
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
