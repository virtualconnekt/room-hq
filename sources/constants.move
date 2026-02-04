/// ============================================================
/// MODULE: Constants
/// SPEC: IMPLEMENTATION_PLAN_FULL.md Day 0-1
/// PURPOSE: Protocol-wide constants (CTO-locked values)
/// ============================================================
module aptosroom::constants {

    // ============================================================
    // ROOM STATES (7-state machine)
    // ============================================================
    
    /// Room state: Initial creation, escrow locked
    public fun STATE_INIT(): u8 { 0 }
    
    /// Room state: Open for submissions
    public fun STATE_OPEN(): u8 { 1 }
    
    /// Room state: Submissions closed, awaiting jury
    public fun STATE_CLOSED(): u8 { 2 }
    
    /// Room state: Jury commit phase active
    public fun STATE_JURY_ACTIVE(): u8 { 3 }
    
    /// Room state: Jury reveal phase
    public fun STATE_JURY_REVEAL(): u8 { 4 }
    
    /// Room state: Scores computed, awaiting client approval
    public fun STATE_FINALIZED(): u8 { 5 }
    
    /// Room state: Payout complete, terminal state
    public fun STATE_SETTLED(): u8 { 6 }

    // ============================================================
    // SCORING PARAMETERS
    // ============================================================
    
    /// Maximum score a juror can give (0-100 scale)
    public fun MAX_SCORE(): u64 { 100 }
    
    /// Minimum score (floor)
    public fun MIN_SCORE(): u64 { 0 }
    
    /// Variance threshold for nearest-neighbor outlier detection
    /// CTO-LOCKED: If min_distance > 15, juror is flagged
    public fun VARIANCE_THRESHOLD(): u64 { 15 }

    // ============================================================
    // JURY PARAMETERS
    // ============================================================
    
    /// Default jury size per room
    public fun JURY_SIZE(): u64 { 5 }
    
    /// Minimum jury size (must have at least this many eligible jurors)
    public fun JURY_SIZE_MIN(): u64 { 3 }

    // ============================================================
    // DUAL-KEY CONSENSUS WEIGHTS
    // ============================================================
    
    /// Client score weight (Gold Key) - 60%
    public fun CLIENT_WEIGHT(): u64 { 60 }
    
    /// Jury score weight (Silver Key) - 40%
    public fun JURY_WEIGHT(): u64 { 40 }
    
    /// Weight denominator for percentage calculation
    public fun WEIGHT_DENOMINATOR(): u64 { 100 }

    // ============================================================
    // TIMING PARAMETERS (in seconds)
    // ============================================================

    /// Submission window duration: 7 days
    public fun SUBMIT_WINDOW_SECONDS(): u64 { 604800 }
    
    /// Jury commit window duration: 3 days
    public fun COMMIT_WINDOW_SECONDS(): u64 { 259200 }
    
    /// Jury reveal window duration: 2 days
    public fun REVEAL_WINDOW_SECONDS(): u64 { 172800 }
    
    /// Client approval window duration: 3 days
    public fun APPROVAL_WINDOW_SECONDS(): u64 { 259200 }

    // ============================================================
    // TIER SYSTEM PARAMETERS
    // ============================================================

    /// Tier identifiers
    public fun TIER_A(): u8 { 1 }
    public fun TIER_B(): u8 { 2 }
    public fun TIER_C(): u8 { 3 }

    /// Tier jury scores (added to 60% client score)
    /// Tier A: Excellent - top performers
    public fun TIER_A_SCORE(): u64 { 40 }
    /// Tier B: Good - above average
    public fun TIER_B_SCORE(): u64 { 30 }
    /// Tier C: General - default tier
    public fun TIER_C_SCORE(): u64 { 20 }

    /// Slot thresholds for tier allocation
    public fun SLOT_THRESHOLD_LOW(): u64 { 10 }
    public fun SLOT_THRESHOLD_HIGH(): u64 { 20 }

    /// Tier A slots by contributor count
    /// < 10 contributors: 1 slot
    public fun TIER_A_SLOTS_LOW(): u64 { 1 }
    /// 10-20 contributors: 3 slots
    public fun TIER_A_SLOTS_MID(): u64 { 3 }
    /// > 20 contributors: 5 slots
    public fun TIER_A_SLOTS_HIGH(): u64 { 5 }

    /// Tier B slots by contributor count
    /// < 10 contributors: 2 slots
    public fun TIER_B_SLOTS_LOW(): u64 { 2 }
    /// 10-20 contributors: 4 slots
    public fun TIER_B_SLOTS_MID(): u64 { 4 }
    /// > 20 contributors: 7 slots
    public fun TIER_B_SLOTS_HIGH(): u64 { 7 }

    /// Get Tier A slots based on contributor count
    public fun get_tier_a_slots(contributor_count: u64): u64 {
        if (contributor_count < SLOT_THRESHOLD_LOW()) {
            TIER_A_SLOTS_LOW()
        } else if (contributor_count <= SLOT_THRESHOLD_HIGH()) {
            TIER_A_SLOTS_MID()
        } else {
            TIER_A_SLOTS_HIGH()
        }
    }

    /// Get Tier B slots based on contributor count
    public fun get_tier_b_slots(contributor_count: u64): u64 {
        if (contributor_count < SLOT_THRESHOLD_LOW()) {
            TIER_B_SLOTS_LOW()
        } else if (contributor_count <= SLOT_THRESHOLD_HIGH()) {
            TIER_B_SLOTS_MID()
        } else {
            TIER_B_SLOTS_HIGH()
        }
    }

    /// Convert tier to jury score
    public fun tier_to_score(tier: u8): u64 {
        if (tier == TIER_A()) {
            TIER_A_SCORE()
        } else if (tier == TIER_B()) {
            TIER_B_SCORE()
        } else {
            TIER_C_SCORE()
        }
    }

    // ============================================================
    // TESTS
    // ============================================================
    
    #[test]
    fun test_state_values_unique() {
        assert!(STATE_INIT() != STATE_OPEN(), 0);
        assert!(STATE_OPEN() != STATE_CLOSED(), 0);
        assert!(STATE_CLOSED() != STATE_JURY_ACTIVE(), 0);
        assert!(STATE_JURY_ACTIVE() != STATE_JURY_REVEAL(), 0);
        assert!(STATE_JURY_REVEAL() != STATE_FINALIZED(), 0);
        assert!(STATE_FINALIZED() != STATE_SETTLED(), 0);
    }
    
    #[test]
    fun test_weights_sum_to_100() {
        assert!(CLIENT_WEIGHT() + JURY_WEIGHT() == WEIGHT_DENOMINATOR(), 0);
    }
    
    #[test]
    fun test_variance_threshold_is_15() {
        assert!(VARIANCE_THRESHOLD() == 15, 0);
    }

    #[test]
    fun test_tier_scores() {
        assert!(TIER_A_SCORE() == 40, 0);
        assert!(TIER_B_SCORE() == 30, 0);
        assert!(TIER_C_SCORE() == 20, 0);
    }

    #[test]
    fun test_tier_slots_low() {
        // < 10 contributors
        assert!(get_tier_a_slots(5) == 1, 0);
        assert!(get_tier_b_slots(5) == 2, 0);
    }

    #[test]
    fun test_tier_slots_mid() {
        // 10-20 contributors
        assert!(get_tier_a_slots(15) == 3, 0);
        assert!(get_tier_b_slots(15) == 4, 0);
    }

    #[test]
    fun test_tier_slots_high() {
        // > 20 contributors
        assert!(get_tier_a_slots(25) == 5, 0);
        assert!(get_tier_b_slots(25) == 7, 0);
    }

    #[test]
    fun test_tier_to_score() {
        assert!(tier_to_score(TIER_A()) == 40, 0);
        assert!(tier_to_score(TIER_B()) == 30, 0);
        assert!(tier_to_score(TIER_C()) == 20, 0);
    }
}
