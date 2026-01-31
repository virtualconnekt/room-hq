/// ============================================================
/// MODULE: Keycard
/// SPEC: EXECUTION_TASKS_BY_PHASE.md Section 2.1
/// INVARIANTS ENFORCED:
///   - INVARIANT_KEYCARD_001: Soulbound (non-transferable)
///   - INVARIANT_KEYCARD_002: One per address
/// ============================================================
module aptosroom::keycard {
    use std::signer;
    use std::string::String;
    use std::vector;
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use aptosroom::errors;

    // ============================================================
    // STRUCTS
    // ============================================================

    /// Soulbound identity token for protocol participants
    /// Stored directly in user's account (not transferable)
    struct Keycard has key {
        /// Unique identifier
        id: u64,
        /// Owner address (redundant but useful for queries)
        owner: address,
        /// Number of tasks completed as contributor
        tasks_completed: u64,
        /// Weighted average score across all completed tasks
        avg_score: u64,
        /// Number of jury participations
        jury_participations: u64,
        /// Number of times flagged for variance
        variance_flags: u64,
        /// Categories this keycard holder is eligible for
        categories: vector<String>,
        /// Timestamp of keycard creation
        created_at: u64,
    }

    /// Capability for protocol to update keycard stats
    /// Only held by authorized modules
    struct KeycardMutator has key {
        /// Dummy field for capability pattern
        dummy: bool,
    }

    // ============================================================
    // EVENTS
    // ============================================================

    #[event]
    struct KeycardMinted has drop, store {
        owner: address,
        keycard_id: u64,
        timestamp: u64,
    }

    #[event]
    struct KeycardStatsUpdated has drop, store {
        owner: address,
        tasks_completed: u64,
        avg_score: u64,
        jury_participations: u64,
        variance_flags: u64,
    }

    // ============================================================
    // GLOBAL ID COUNTER
    // ============================================================

    struct KeycardCounter has key {
        next_id: u64,
    }

    /// Initialize the keycard counter (called once at module publish)
    fun init_module(account: &signer) {
        move_to(account, KeycardCounter { next_id: 1 });
        move_to(account, KeycardMutator { dummy: true });
    }

    // ============================================================
    // PUBLIC ENTRY FUNCTIONS
    // ============================================================

    /// Mint a new keycard for the caller
    /// INVARIANT_KEYCARD_002: One per address - aborts if already exists
    public entry fun mint(account: &signer) acquires KeycardCounter {
        let addr = signer::address_of(account);
        
        // Check: caller does not already have a keycard
        assert!(!exists<Keycard>(addr), errors::E_ALREADY_HAS_KEYCARD());
        
        // Get next ID
        let counter = borrow_global_mut<KeycardCounter>(@aptosroom);
        let keycard_id = counter.next_id;
        counter.next_id = counter.next_id + 1;
        
        // Create keycard with zeroed stats
        let keycard = Keycard {
            id: keycard_id,
            owner: addr,
            tasks_completed: 0,
            avg_score: 0,
            jury_participations: 0,
            variance_flags: 0,
            categories: vector::empty<String>(),
            created_at: timestamp::now_seconds(),
        };
        
        // Store in user's account (soulbound - cannot be transferred)
        move_to(account, keycard);
        
        // Emit event
        event::emit(KeycardMinted {
            owner: addr,
            keycard_id,
            timestamp: timestamp::now_seconds(),
        });
    }

    // ============================================================
    // VIEW FUNCTIONS
    // ============================================================

    #[view]
    /// Check if an address has a keycard
    public fun has_keycard(addr: address): bool {
        exists<Keycard>(addr)
    }

    #[view]
    /// Get keycard ID for an address
    public fun get_keycard_id(addr: address): u64 acquires Keycard {
        assert!(exists<Keycard>(addr), errors::E_KEYCARD_NOT_FOUND());
        borrow_global<Keycard>(addr).id
    }

    #[view]
    /// Get tasks completed count
    public fun get_tasks_completed(addr: address): u64 acquires Keycard {
        assert!(exists<Keycard>(addr), errors::E_KEYCARD_NOT_FOUND());
        borrow_global<Keycard>(addr).tasks_completed
    }

    #[view]
    /// Get average score
    public fun get_avg_score(addr: address): u64 acquires Keycard {
        assert!(exists<Keycard>(addr), errors::E_KEYCARD_NOT_FOUND());
        borrow_global<Keycard>(addr).avg_score
    }

    #[view]
    /// Get jury participations count
    public fun get_jury_participations(addr: address): u64 acquires Keycard {
        assert!(exists<Keycard>(addr), errors::E_KEYCARD_NOT_FOUND());
        borrow_global<Keycard>(addr).jury_participations
    }

    #[view]
    /// Get variance flags count
    public fun get_variance_flags(addr: address): u64 acquires Keycard {
        assert!(exists<Keycard>(addr), errors::E_KEYCARD_NOT_FOUND());
        borrow_global<Keycard>(addr).variance_flags
    }

    // ============================================================
    // INTERNAL FUNCTIONS (called by other modules via capability)
    // ============================================================

    /// Add a completed task to keycard stats
    /// Called by settlement module after room settles
    // TODO: Implement add_task_completion(
    //   addr: address,
    //   room_id: u64,
    //   category: String,
    //   score: u64,
    // )
    // Steps:
    // 1. Assert has_keycard(addr)
    // 2. Borrow keycard mutably
    // 3. Increment tasks_completed
    // 4. Update avg_score using weighted average formula:
    //    new_avg = ((old_avg * old_count) + new_score) / new_count
    // 5. Emit KeycardStatsUpdated event

    /// Increment jury participation count
    /// Called by jury module when juror participates
    // TODO: Implement increment_jury_participations(addr: address)
    // Steps:
    // 1. Assert has_keycard(addr)
    // 2. Borrow keycard mutably
    // 3. Increment jury_participations
    // 4. Emit KeycardStatsUpdated event

    /// Increment variance flags count
    /// Called by variance module when juror is flagged
    // TODO: Implement increment_variance_flags(addr: address)
    // Steps:
    // 1. Assert has_keycard(addr)
    // 2. Borrow keycard mutably
    // 3. Increment variance_flags
    // 4. Emit KeycardStatsUpdated event

    /// Add a category to keycard
    // TODO: Implement add_category(addr: address, category: String)
    // Steps:
    // 1. Assert has_keycard(addr)
    // 2. Assert category not already in list
    // 3. Push category to categories vector

    /// Check if keycard holder is eligible for a category
    // TODO: Implement is_eligible_for_category(addr: address, category: &String): bool
    // Steps:
    // 1. Return false if no keycard
    // 2. Check if category is in categories vector

    // ============================================================
    // SOULBOUND ENFORCEMENT
    // ============================================================
    
    // INVARIANT_KEYCARD_001: Soulbound (non-transferable)
    // 
    // Enforcement: Keycard struct has `key` ability only (no `store`).
    // This means:
    // - Cannot be wrapped in another struct
    // - Cannot be transferred via `move_to` by another account
    // - Can only exist at the account that created it
    //
    // The Move type system enforces this automatically.
    // No transfer function is implemented.
}
