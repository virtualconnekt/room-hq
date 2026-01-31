/// ============================================================
/// MODULE: JurorRegistry
/// SPEC: EXECUTION_TASKS_BY_PHASE.md Section 2.1
/// PURPOSE: Manage juror eligibility by category
/// ============================================================
module aptosroom::juror_registry {
    use std::signer;
    use std::string::String;
    use std::vector;
    use aptos_std::table::{Self, Table};
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use aptosroom::errors;
    use aptosroom::keycard;

    // ============================================================
    // STRUCTS
    // ============================================================

    /// Global registry of jurors by category
    struct JurorRegistry has key {
        /// Map: category -> list of registered juror addresses
        categories: Table<String, vector<address>>,
    }

    /// Tracks which categories a specific juror is registered for
    struct JurorProfile has key {
        /// Categories this juror is registered for
        registered_categories: vector<String>,
    }

    // ============================================================
    // EVENTS
    // ============================================================

    #[event]
    struct JurorRegistered has drop, store {
        juror: address,
        category: String,
        timestamp: u64,
    }

    #[event]
    struct JurorUnregistered has drop, store {
        juror: address,
        category: String,
        timestamp: u64,
    }

    // ============================================================
    // INITIALIZATION
    // ============================================================

    /// Initialize the juror registry (called once at module publish)
    fun init_module(account: &signer) {
        move_to(account, JurorRegistry {
            categories: table::new<String, vector<address>>(),
        });
    }

    // ============================================================
    // PUBLIC ENTRY FUNCTIONS
    // ============================================================

    /// Register caller as juror for a category
    /// Requires: caller has a keycard
    public entry fun register_for_category(
        account: &signer,
        category: String,
    ) acquires JurorRegistry, JurorProfile {
        let juror_addr = signer::address_of(account);
        
        // Must have keycard to be juror
        assert!(keycard::has_keycard(juror_addr), errors::E_NO_KEYCARD());
        
        // Initialize profile if needed
        if (!exists<JurorProfile>(juror_addr)) {
            move_to(account, JurorProfile {
                registered_categories: vector::empty<String>(),
            });
        };
        
        let profile = borrow_global_mut<JurorProfile>(juror_addr);
        
        // Check not already registered for this category
        assert!(
            !vector::contains(&profile.registered_categories, &category),
            errors::E_ALREADY_REGISTERED()
        );
        
        // Add to profile
        vector::push_back(&mut profile.registered_categories, category);
        
        // Add to global registry
        let registry = borrow_global_mut<JurorRegistry>(@aptosroom);
        if (!table::contains(&registry.categories, category)) {
            table::add(&mut registry.categories, category, vector::empty<address>());
        };
        let category_jurors = table::borrow_mut(&mut registry.categories, category);
        vector::push_back(category_jurors, juror_addr);
        
        // Emit event
        event::emit(JurorRegistered {
            juror: juror_addr,
            category,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Unregister caller from a category
    public entry fun unregister_from_category(
        account: &signer,
        category: String,
    ) acquires JurorRegistry, JurorProfile {
        let juror_addr = signer::address_of(account);
        
        assert!(exists<JurorProfile>(juror_addr), errors::E_NOT_REGISTERED());
        
        let profile = borrow_global_mut<JurorProfile>(juror_addr);
        
        // Find and remove from profile
        let (found, index) = vector::index_of(&profile.registered_categories, &category);
        assert!(found, errors::E_NOT_REGISTERED());
        vector::remove(&mut profile.registered_categories, index);
        
        // Remove from global registry
        let registry = borrow_global_mut<JurorRegistry>(@aptosroom);
        if (table::contains(&registry.categories, category)) {
            let category_jurors = table::borrow_mut(&mut registry.categories, category);
            let (found_in_registry, idx) = vector::index_of(category_jurors, &juror_addr);
            if (found_in_registry) {
                vector::remove(category_jurors, idx);
            };
        };
        
        // Emit event
        event::emit(JurorUnregistered {
            juror: juror_addr,
            category,
            timestamp: timestamp::now_seconds(),
        });
    }

    // ============================================================
    // VIEW FUNCTIONS
    // ============================================================

    #[view]
    /// Check if address is registered as juror for a category
    public fun is_registered(juror_addr: address, category: String): bool acquires JurorProfile {
        if (!exists<JurorProfile>(juror_addr)) {
            return false
        };
        let profile = borrow_global<JurorProfile>(juror_addr);
        vector::contains(&profile.registered_categories, &category)
    }

    #[view]
    /// Get all registered categories for a juror
    public fun get_registered_categories(juror_addr: address): vector<String> acquires JurorProfile {
        if (!exists<JurorProfile>(juror_addr)) {
            return vector::empty<String>()
        };
        borrow_global<JurorProfile>(juror_addr).registered_categories
    }

    // ============================================================
    // INTERNAL FUNCTIONS (for jury selection)
    // ============================================================

    // Friend declarations for modules that need to query jurors
    friend aptosroom::jury;

    /// Get list of eligible jurors for a category
    public(friend) fun get_eligible_jurors(category: &String): vector<address> acquires JurorRegistry {
        let registry = borrow_global<JurorRegistry>(@aptosroom);
        if (!table::contains(&registry.categories, *category)) {
            return vector::empty<address>()
        };
        *table::borrow(&registry.categories, *category)
    }

    /// Get count of eligible jurors for a category
    public fun get_eligible_juror_count(category: &String): u64 acquires JurorRegistry {
        let registry = borrow_global<JurorRegistry>(@aptosroom);
        if (!table::contains(&registry.categories, *category)) {
            return 0
        };
        vector::length(table::borrow(&registry.categories, *category))
    }

    /// Check if there are enough jurors for selection
    public fun has_sufficient_jurors(category: &String, required: u64): bool acquires JurorRegistry {
        get_eligible_juror_count(category) >= required
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
    /// Test helper to get eligible jurors
    public fun test_get_eligible_jurors(category: &String): vector<address> acquires JurorRegistry {
        get_eligible_jurors(category)
    }
}
