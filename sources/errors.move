/// ============================================================
/// MODULE: Errors
/// SPEC: IMPLEMENTATION_PLAN_FULL.md Day 0-1
/// PURPOSE: Centralized error codes for all modules
/// CONVENTION: E_<MODULE>_<ERROR_NAME>
/// ============================================================
module aptosroom::errors {

    // ============================================================
    // KEYCARD ERRORS (100-199)
    // ============================================================
    
    /// Caller already has a keycard (INVARIANT_KEYCARD_002)
    public fun E_ALREADY_HAS_KEYCARD(): u64 { 100 }
    
    /// Caller does not have a keycard
    public fun E_NO_KEYCARD(): u64 { 101 }
    
    /// Keycard transfer attempted (INVARIANT_KEYCARD_001)
    public fun E_SOULBOUND_NO_TRANSFER(): u64 { 102 }
    
    /// Keycard not found at address
    public fun E_KEYCARD_NOT_FOUND(): u64 { 103 }

    // ============================================================
    // JUROR REGISTRY ERRORS (200-299)
    // ============================================================
    
    /// Juror already registered for this category
    public fun E_ALREADY_REGISTERED(): u64 { 200 }
    
    /// Juror not registered for required category
    public fun E_NOT_REGISTERED(): u64 { 201 }
    
    /// Insufficient jurors available for selection
    public fun E_INSUFFICIENT_JURORS(): u64 { 202 }
    
    /// Address is not an assigned juror for this room
    public fun E_NOT_JUROR(): u64 { 203 }

    // ============================================================
    // VAULT ERRORS (300-399)
    // ============================================================
    
    /// Vault is locked, cannot withdraw (INVARIANT_ROOM_003)
    public fun E_VAULT_LOCKED(): u64 { 300 }
    
    /// Insufficient balance in vault
    public fun E_INSUFFICIENT_BALANCE(): u64 { 301 }
    
    /// Escrow amount less than task reward
    public fun E_INSUFFICIENT_ESCROW(): u64 { 302 }
    
    /// Vault already exists for this room
    public fun E_VAULT_EXISTS(): u64 { 303 }

    // ============================================================
    // ROOM ERRORS (400-499)
    // ============================================================
    
    /// Invalid state transition (INVARIANT_ROOM_001)
    public fun E_INVALID_STATE_TRANSITION(): u64 { 400 }
    
    /// Room is not in OPEN state
    public fun E_ROOM_NOT_OPEN(): u64 { 401 }
    
    /// Room is not in expected state
    public fun E_WRONG_STATE(): u64 { 402 }
    
    /// State is terminal, no transitions allowed (INVARIANT_ROOM_004)
    public fun E_STATE_IS_TERMINAL(): u64 { 403 }
    
    /// Caller is not the room client
    public fun E_NOT_CLIENT(): u64 { 404 }
    
    /// Room not found
    public fun E_ROOM_NOT_FOUND(): u64 { 405 }

    // ============================================================
    // SUBMISSION ERRORS (500-599)
    // ============================================================
    
    /// Duplicate submission from same contributor (INVARIANT_SUBMISSION_001)
    public fun E_DUPLICATE_SUBMISSION(): u64 { 500 }
    
    /// Submission deadline has passed
    public fun E_DEADLINE_PASSED(): u64 { 501 }
    
    /// Submission not found
    public fun E_SUBMISSION_NOT_FOUND(): u64 { 502 }

    // ============================================================
    // JURY / VOTING ERRORS (600-699)
    // ============================================================
    
    /// Not in commit phase
    public fun E_NOT_IN_COMMIT_PHASE(): u64 { 600 }
    
    /// Not in reveal phase
    public fun E_NOT_IN_REVEAL_PHASE(): u64 { 601 }
    
    /// Vote already committed
    public fun E_ALREADY_COMMITTED(): u64 { 602 }
    
    /// Vote already revealed
    public fun E_ALREADY_REVEALED(): u64 { 603 }
    
    /// Vote not committed yet
    public fun E_NOT_COMMITTED(): u64 { 604 }
    
    /// Hash mismatch on reveal (INVARIANT_VOTE_001)
    public fun E_HASH_MISMATCH(): u64 { 605 }
    
    /// Score out of valid range
    public fun E_INVALID_SCORE(): u64 { 606 }
    
    /// Commit deadline passed
    public fun E_COMMIT_DEADLINE_PASSED(): u64 { 607 }
    
    /// Reveal deadline passed
    public fun E_REVEAL_DEADLINE_PASSED(): u64 { 608 }
    
    /// Jury not selected for room
    public fun E_JURY_NOT_SELECTED(): u64 { 609 }
    
    /// Commit phase not complete
    public fun E_COMMIT_PHASE_NOT_COMPLETE(): u64 { 610 }

    /// Invalid tier A selection count (must match required slots)
    public fun E_INVALID_TIER_A_COUNT(): u64 { 611 }

    /// Invalid tier B selection count (must match required slots)
    public fun E_INVALID_TIER_B_COUNT(): u64 { 612 }

    /// Duplicate contributor found in tier selections
    public fun E_DUPLICATE_IN_TIERS(): u64 { 613 }

    /// Selected address is not a valid contributor
    public fun E_NOT_A_CONTRIBUTOR(): u64 { 614 }

    /// Tier votes not yet computed
    public fun E_TIERS_NOT_COMPUTED(): u64 { 615 }

    // ============================================================
    // SETTLEMENT ERRORS (700-799)
    // ============================================================
    
    /// Room not in FINALIZED state
    public fun E_NOT_FINALIZED(): u64 { 700 }
    
    /// Jury score not yet computed
    public fun E_JURY_NOT_FINALIZED(): u64 { 701 }
    
    /// Client has not approved settlement (INVARIANT_DUAL_KEY_001)
    public fun E_CLIENT_NOT_APPROVED(): u64 { 702 }
    
    /// Client approval already given
    public fun E_APPROVAL_ALREADY_GIVEN(): u64 { 703 }
    
    /// No valid votes after variance filtering
    public fun E_NO_VALID_VOTES(): u64 { 704 }

    // ============================================================
    // GENERAL ERRORS (900-999)
    // ============================================================
    
    /// Unauthorized caller
    public fun E_UNAUTHORIZED(): u64 { 900 }
    
    /// Invalid argument
    public fun E_INVALID_ARGUMENT(): u64 { 901 }
    
    /// Operation not permitted
    public fun E_NOT_PERMITTED(): u64 { 902 }
}
