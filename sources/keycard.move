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
    // INTERNAL FUNCTIONS (called by other modules via friend)
    // ============================================================

    // Friend declarations for modules that can update keycard stats
    friend aptosroom::settlement;
    friend aptosroom::jury;
    friend aptosroom::variance;

    /// Add a completed task to keycard stats
    /// Called by settlement module after room settles
    /// Uses weighted average formula: new_avg = ((old_avg * old_count) + new_score) / new_count
    public(friend) fun add_task_completion(
        addr: address,
        score: u64,
    ) acquires Keycard {
        assert!(exists<Keycard>(addr), errors::E_KEYCARD_NOT_FOUND());
        
        let keycard = borrow_global_mut<Keycard>(addr);
        let old_count = keycard.tasks_completed;
        let old_avg = keycard.avg_score;
        
        // Increment task count
        keycard.tasks_completed = old_count + 1;
        
        // Calculate new weighted average
        // new_avg = ((old_avg * old_count) + new_score) / new_count
        let new_count = keycard.tasks_completed;
        keycard.avg_score = ((old_avg * old_count) + score) / new_count;
        
        // Emit event
        event::emit(KeycardStatsUpdated {
            owner: addr,
            tasks_completed: keycard.tasks_completed,
            avg_score: keycard.avg_score,
            jury_participations: keycard.jury_participations,
            variance_flags: keycard.variance_flags,
        });
    }

    /// Increment jury participation count
    /// Called by jury module when juror reveals their vote
    public(friend) fun increment_jury_participations(addr: address) acquires Keycard {
        assert!(exists<Keycard>(addr), errors::E_KEYCARD_NOT_FOUND());
        
        let keycard = borrow_global_mut<Keycard>(addr);
        keycard.jury_participations = keycard.jury_participations + 1;
        
        // Emit event
        event::emit(KeycardStatsUpdated {
            owner: addr,
            tasks_completed: keycard.tasks_completed,
            avg_score: keycard.avg_score,
            jury_participations: keycard.jury_participations,
            variance_flags: keycard.variance_flags,
        });
    }

    /// Increment variance flags count
    /// Called by variance module when juror vote is flagged as outlier
    public(friend) fun increment_variance_flags(addr: address) acquires Keycard {
        assert!(exists<Keycard>(addr), errors::E_KEYCARD_NOT_FOUND());
        
        let keycard = borrow_global_mut<Keycard>(addr);
        keycard.variance_flags = keycard.variance_flags + 1;
        
        // Emit event
        event::emit(KeycardStatsUpdated {
            owner: addr,
            tasks_completed: keycard.tasks_completed,
            avg_score: keycard.avg_score,
            jury_participations: keycard.jury_participations,
            variance_flags: keycard.variance_flags,
        });
    }

    /// Add a category to keycard holder's eligible categories
    public(friend) fun add_category(addr: address, category: String) acquires Keycard {
        assert!(exists<Keycard>(addr), errors::E_KEYCARD_NOT_FOUND());
        
        let keycard = borrow_global_mut<Keycard>(addr);
        
        // Check category not already in list
        assert!(
            !vector::contains(&keycard.categories, &category),
            errors::E_ALREADY_REGISTERED()
        );
        
        vector::push_back(&mut keycard.categories, category);
    }

    /// Check if keycard holder is eligible for a category
    public fun is_eligible_for_category(addr: address, category: &String): bool acquires Keycard {
        if (!exists<Keycard>(addr)) {
            return false
        };
        let keycard = borrow_global<Keycard>(addr);
        vector::contains(&keycard.categories, category)
    }

    // ============================================================
    // TEST-ONLY FUNCTIONS
    // ============================================================

    #[test_only]
    /// Initialize module for testing
    public fun init_for_test(account: &signer) {
        init_module(account);
    }

    #[test_only]
    /// Test helper to add task completion
    public fun test_add_task_completion(addr: address, score: u64) acquires Keycard {
        add_task_completion(addr, score);
    }

    #[test_only]
    /// Test helper to increment jury participations
    public fun test_increment_jury_participations(addr: address) acquires Keycard {
        increment_jury_participations(addr);
    }

    #[test_only]
    /// Test helper to increment variance flags
    public fun test_increment_variance_flags(addr: address) acquires Keycard {
        increment_variance_flags(addr);
    }

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
