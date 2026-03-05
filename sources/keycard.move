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
    use std::option::{Self, Option};
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use aptosroom::errors;
    use aptosroom::constants;

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
        /// Total lifetime variance flags
        variance_flags: u64,
        /// Consecutive variance flags (resets on successful task completion)
        /// INVARIANT_KEYCARD_001: 2 consecutive flags → is_suspended = true
        consecutive_flags: u8,
        /// Room ID of last variance flag (for consecutive detection)
        last_flagged_room_id: Option<u64>,
        /// Whether this keycard holder is currently suspended
        is_suspended: bool,
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

    #[event]
    struct KeycardSuspended has drop, store {
        owner: address,
        consecutive_flags: u8,
        timestamp: u64,
    }

    #[event]
    struct KeycardUnsuspended has drop, store {
        owner: address,
        timestamp: u64,
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
            consecutive_flags: 0,
            last_flagged_room_id: option::none<u64>(),
            is_suspended: false,
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

    #[view]
    /// Get consecutive variance flags count
    public fun get_consecutive_flags(addr: address): u8 acquires Keycard {
        assert!(exists<Keycard>(addr), errors::E_KEYCARD_NOT_FOUND());
        borrow_global<Keycard>(addr).consecutive_flags
    }

    #[view]
    /// Check if this keycard holder is suspended
    /// INVARIANT_KEYCARD_001: Suspended jurors cannot be selected for jury
    public fun is_suspended(addr: address): bool acquires Keycard {
        if (!exists<Keycard>(addr)) { return false };
        borrow_global<Keycard>(addr).is_suspended
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
    /// Also resets consecutive flags if score >= MIN_TASK_SCORE_FOR_UNSUSPEND (unsuspend path)
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

        // UNSUSPEND PATH: If task score >= threshold, reset consecutive flags
        // This is the only way to recover from suspension.
        // Spec: score >= 75 resets consecutive_flags and lifts suspension.
        let was_suspended = keycard.is_suspended;
        if (score >= constants::MIN_TASK_SCORE_FOR_UNSUSPEND()) {
            keycard.consecutive_flags = 0;
            keycard.last_flagged_room_id = option::none<u64>();
            keycard.is_suspended = false;
        };
        
        // Emit unsuspend event if they were suspended and are now unsuspended
        if (was_suspended && !keycard.is_suspended) {
            event::emit(KeycardUnsuspended {
                owner: addr,
                timestamp: timestamp::now_seconds(),
            });
        };

        // Emit stats update event
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

    /// Increment variance flags count with consecutive tracking
    /// Called by variance module when juror vote is flagged as outlier
    /// INVARIANT_KEYCARD_001: 2 consecutive flags (from different rooms) → auto-suspend
    public(friend) fun increment_variance_flags(addr: address, room_id: u64) acquires Keycard {
        assert!(exists<Keycard>(addr), errors::E_KEYCARD_NOT_FOUND());
        
        let keycard = borrow_global_mut<Keycard>(addr);

        // Increment total lifetime flags
        keycard.variance_flags = keycard.variance_flags + 1;

        // Determine if this flag is consecutive with the previous one.
        // Consecutive = flagged in a DIFFERENT room from the last flag
        // (same room twice doesn't count as consecutive — only across rooms).
        let is_new_consecutive = if (option::is_some(&keycard.last_flagged_room_id)) {
            let prev_room = *option::borrow(&keycard.last_flagged_room_id);
            prev_room != room_id // flagged in a different room = consecutive
        } else {
            true // first flag ever = start of consecutive chain
        };

        if (is_new_consecutive) {
            keycard.consecutive_flags = keycard.consecutive_flags + 1;
        };
        // Always update to this room as last flagged
        keycard.last_flagged_room_id = option::some(room_id);

        // INVARIANT_KEYCARD_001: 2+ consecutive flags → suspend
        let consecutive = keycard.consecutive_flags;
        let threshold = (constants::CONSECUTIVE_FLAGS_THRESHOLD() as u8);
        if (consecutive >= threshold && !keycard.is_suspended) {
            keycard.is_suspended = true;
            event::emit(KeycardSuspended {
                owner: addr,
                consecutive_flags: consecutive,
                timestamp: timestamp::now_seconds(),
            });
        };

        // Emit stats update event
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
