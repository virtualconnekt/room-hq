/// ============================================================
/// TEST MODULE: Keycard Tests
/// SPEC: TEST_PLAN.md Section 5.1
/// PURPOSE: Unit tests for Keycard and JurorRegistry modules
/// ============================================================
#[test_only]
module aptosroom::keycard_tests {
    use std::signer;
    use std::string;
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use aptosroom::keycard;
    use aptosroom::juror_registry;

    // ============================================================
    // TEST SETUP HELPERS
    // ============================================================

    /// Setup test environment with timestamp and module initialization
    fun setup_test_env(framework: &signer, aptosroom_account: &signer) {
        // Initialize timestamp for testing (required by keycard::mint)
        timestamp::set_time_has_started_for_testing(framework);
        
        // Initialize keycard module
        keycard::init_for_test(aptosroom_account);
        
        // Initialize juror registry module
        juror_registry::init_for_test(aptosroom_account);
    }

    /// Create a test account at a given address
    fun create_test_account(addr: address): signer {
        account::create_account_for_test(addr)
    }

    // ============================================================
    // KEYCARD MINT TESTS
    // ============================================================

    #[test(framework = @0x1, aptosroom = @aptosroom)]
    /// Test successful keycard minting
    fun test_keycard_mint_success(framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);
        
        // Create user account
        let user = create_test_account(@0x123);
        let user_addr = signer::address_of(&user);
        
        // Initially no keycard
        assert!(!keycard::has_keycard(user_addr), 0);
        
        // Mint keycard
        keycard::mint(&user);
        
        // Verify keycard exists
        assert!(keycard::has_keycard(user_addr), 1);
        
        // Verify stats are zero
        assert!(keycard::get_tasks_completed(user_addr) == 0, 2);
        assert!(keycard::get_avg_score(user_addr) == 0, 3);
        assert!(keycard::get_jury_participations(user_addr) == 0, 4);
        assert!(keycard::get_variance_flags(user_addr) == 0, 5);
    }

    #[test(framework = @0x1, aptosroom = @aptosroom)]
    /// Test keycard stats initialized to zero
    fun test_keycard_stats_initialized_zero(framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);
        
        let user = create_test_account(@0x123);
        let user_addr = signer::address_of(&user);
        
        keycard::mint(&user);
        
        assert!(keycard::get_tasks_completed(user_addr) == 0, 0);
        assert!(keycard::get_avg_score(user_addr) == 0, 1);
        assert!(keycard::get_jury_participations(user_addr) == 0, 2);
        assert!(keycard::get_variance_flags(user_addr) == 0, 3);
    }

    #[test(framework = @0x1, aptosroom = @aptosroom)]
    #[expected_failure(abort_code = 100)] // E_ALREADY_HAS_KEYCARD
    /// Test duplicate mint is rejected (INVARIANT_KEYCARD_002)
    fun test_keycard_duplicate_mint_rejected(framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);
        
        let user = create_test_account(@0x123);
        
        // First mint succeeds
        keycard::mint(&user);
        
        // Second mint should fail
        keycard::mint(&user);
    }

    #[test(framework = @0x1, aptosroom = @aptosroom)]
    /// Test keycard ID is unique and increments
    fun test_keycard_id_increments(framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);
        
        let user1 = create_test_account(@0x111);
        let user2 = create_test_account(@0x222);
        
        keycard::mint(&user1);
        keycard::mint(&user2);
        
        let id1 = keycard::get_keycard_id(signer::address_of(&user1));
        let id2 = keycard::get_keycard_id(signer::address_of(&user2));
        
        assert!(id1 == 1, 0);
        assert!(id2 == 2, 1);
    }

    // ============================================================
    // JUROR REGISTRY TESTS
    // ============================================================

    #[test(framework = @0x1, aptosroom = @aptosroom)]
    /// Test successful juror registration
    fun test_juror_registration_success(framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);
        
        let juror = create_test_account(@0x123);
        let juror_addr = signer::address_of(&juror);
        
        // Mint keycard first (required for registration)
        keycard::mint(&juror);
        
        // Register for design category
        let design = string::utf8(b"design");
        juror_registry::register_for_category(&juror, design);
        
        // Verify registration
        assert!(juror_registry::is_registered(juror_addr, string::utf8(b"design")), 0);
    }

    #[test(framework = @0x1, aptosroom = @aptosroom)]
    #[expected_failure(abort_code = 101)] // E_NO_KEYCARD
    /// Test registration without keycard is rejected
    fun test_juror_registration_without_keycard_rejected(framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);
        
        let user = create_test_account(@0x123);
        
        // Try to register without keycard - should fail
        let design = string::utf8(b"design");
        juror_registry::register_for_category(&user, design);
    }

    #[test(framework = @0x1, aptosroom = @aptosroom)]
    #[expected_failure(abort_code = 200)] // E_ALREADY_REGISTERED
    /// Test duplicate registration is rejected
    fun test_juror_duplicate_registration_rejected(framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);
        
        let juror = create_test_account(@0x123);
        keycard::mint(&juror);
        
        let design = string::utf8(b"design");
        
        // First registration succeeds
        juror_registry::register_for_category(&juror, design);
        
        // Second registration should fail
        juror_registry::register_for_category(&juror, string::utf8(b"design"));
    }

    #[test(framework = @0x1, aptosroom = @aptosroom)]
    /// Test juror unregistration
    fun test_juror_unregistration_success(framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);
        
        let juror = create_test_account(@0x123);
        let juror_addr = signer::address_of(&juror);
        keycard::mint(&juror);
        
        let design = string::utf8(b"design");
        
        // Register
        juror_registry::register_for_category(&juror, design);
        assert!(juror_registry::is_registered(juror_addr, string::utf8(b"design")), 0);
        
        // Unregister
        juror_registry::unregister_from_category(&juror, string::utf8(b"design"));
        assert!(!juror_registry::is_registered(juror_addr, string::utf8(b"design")), 1);
    }

    #[test(framework = @0x1, aptosroom = @aptosroom)]
    /// Test multiple category registration
    fun test_juror_multiple_categories(framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);
        
        let juror = create_test_account(@0x123);
        let juror_addr = signer::address_of(&juror);
        keycard::mint(&juror);
        
        // Register for multiple categories
        juror_registry::register_for_category(&juror, string::utf8(b"design"));
        juror_registry::register_for_category(&juror, string::utf8(b"development"));
        juror_registry::register_for_category(&juror, string::utf8(b"writing"));
        
        // Verify all registrations
        assert!(juror_registry::is_registered(juror_addr, string::utf8(b"design")), 0);
        assert!(juror_registry::is_registered(juror_addr, string::utf8(b"development")), 1);
        assert!(juror_registry::is_registered(juror_addr, string::utf8(b"writing")), 2);
        
        // Verify not registered for other categories
        assert!(!juror_registry::is_registered(juror_addr, string::utf8(b"marketing")), 3);
    }

    #[test(framework = @0x1, aptosroom = @aptosroom)]
    /// Test juror count tracking
    fun test_juror_count_tracking(framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);
        
        let design = string::utf8(b"design");
        
        // Initially no jurors
        assert!(juror_registry::get_eligible_juror_count(&design) == 0, 0);
        assert!(!juror_registry::has_sufficient_jurors(&design, 1), 1);
        
        // Add first juror
        let juror1 = create_test_account(@0x111);
        keycard::mint(&juror1);
        juror_registry::register_for_category(&juror1, string::utf8(b"design"));
        
        assert!(juror_registry::get_eligible_juror_count(&design) == 1, 2);
        assert!(juror_registry::has_sufficient_jurors(&design, 1), 3);
        assert!(!juror_registry::has_sufficient_jurors(&design, 2), 4);
        
        // Add second juror
        let juror2 = create_test_account(@0x222);
        keycard::mint(&juror2);
        juror_registry::register_for_category(&juror2, string::utf8(b"design"));
        
        assert!(juror_registry::get_eligible_juror_count(&design) == 2, 5);
        assert!(juror_registry::has_sufficient_jurors(&design, 2), 6);
    }

    // ============================================================
    // KEYCARD STATS UPDATE TESTS
    // ============================================================

    #[test(framework = @0x1, aptosroom = @aptosroom)]
    /// Test task completion updates stats
    fun test_keycard_task_completion_updates_stats(framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);
        
        let user = create_test_account(@0x123);
        let user_addr = signer::address_of(&user);
        keycard::mint(&user);
        
        // Add first task completion with score 80
        keycard::test_add_task_completion(user_addr, 80);
        
        assert!(keycard::get_tasks_completed(user_addr) == 1, 0);
        assert!(keycard::get_avg_score(user_addr) == 80, 1);
    }

    #[test(framework = @0x1, aptosroom = @aptosroom)]
    /// Test variance flag increment
    fun test_keycard_variance_flag_increment(framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);
        
        let user = create_test_account(@0x123);
        let user_addr = signer::address_of(&user);
        keycard::mint(&user);
        
        assert!(keycard::get_variance_flags(user_addr) == 0, 0);
        
        keycard::test_increment_variance_flags(user_addr);
        assert!(keycard::get_variance_flags(user_addr) == 1, 1);
        
        keycard::test_increment_variance_flags(user_addr);
        assert!(keycard::get_variance_flags(user_addr) == 2, 2);
    }

    #[test(framework = @0x1, aptosroom = @aptosroom)]
    /// Test jury participation increment
    fun test_keycard_jury_participation_increment(framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);
        
        let user = create_test_account(@0x123);
        let user_addr = signer::address_of(&user);
        keycard::mint(&user);
        
        assert!(keycard::get_jury_participations(user_addr) == 0, 0);
        
        keycard::test_increment_jury_participations(user_addr);
        assert!(keycard::get_jury_participations(user_addr) == 1, 1);
        
        keycard::test_increment_jury_participations(user_addr);
        assert!(keycard::get_jury_participations(user_addr) == 2, 2);
    }

    #[test(framework = @0x1, aptosroom = @aptosroom)]
    /// Test average score calculation with weighted average
    /// Formula: new_avg = ((old_avg * old_count) + new_score) / new_count
    fun test_keycard_avg_score_calculation(framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);
        
        let user = create_test_account(@0x123);
        let user_addr = signer::address_of(&user);
        keycard::mint(&user);
        
        // First task: score 80, avg = 80
        keycard::test_add_task_completion(user_addr, 80);
        assert!(keycard::get_avg_score(user_addr) == 80, 0);
        
        // Second task: score 90, avg = (80 + 90) / 2 = 85
        keycard::test_add_task_completion(user_addr, 90);
        assert!(keycard::get_avg_score(user_addr) == 85, 1);
        
        // Third task: score 100, avg = (85*2 + 100) / 3 = 270/3 = 90
        keycard::test_add_task_completion(user_addr, 100);
        assert!(keycard::get_avg_score(user_addr) == 90, 2);
        
        // Verify task count
        assert!(keycard::get_tasks_completed(user_addr) == 3, 3);
    }

    #[test(framework = @0x1, aptosroom = @aptosroom)]
    #[expected_failure(abort_code = 103)] // E_KEYCARD_NOT_FOUND
    /// Test stats update fails without keycard
    fun test_stats_update_without_keycard_fails(framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);
        
        // Try to update stats for address without keycard
        keycard::test_add_task_completion(@0x999, 80);
    }
}
