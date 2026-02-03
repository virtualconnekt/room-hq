/// ============================================================
/// TEST MODULE: Room Tests
/// SPEC: TEST_PLAN.md Section 5.2
/// PURPOSE: Unit tests for Vault, Room, and Submission modules
/// ============================================================
#[test_only]
module aptosroom::room_tests {
    use std::signer;
    use std::string;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::timestamp;
    use aptosroom::room;
    use aptosroom::vault;
    use aptosroom::keycard;
    use aptosroom::constants;

    // ============================================================
    // TEST CONSTANTS
    // ============================================================

    const TEST_TASK_REWARD: u64 = 1000000; // 1 APT in octas

    // ============================================================
    // TEST SETUP HELPERS
    // ============================================================

    /// Setup test environment with all required modules
    fun setup_test_env(framework: &signer, aptosroom: &signer) {
        // Initialize timestamp
        timestamp::set_time_has_started_for_testing(framework);

        // Initialize AptosCoin
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(framework);
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);

        // Initialize all aptosroom modules
        keycard::init_for_test(aptosroom);
        vault::init_for_test(aptosroom);
        room::init_for_test(aptosroom);
    }

    /// Create a funded account with APT coins
    fun create_funded_account(framework: &signer, addr: address, amount: u64): signer {
        let acc = account::create_account_for_test(addr);
        coin::register<AptosCoin>(&acc);
        aptos_coin::mint(framework, addr, amount);
        acc
    }

    /// Create a room for testing (client must have keycard)
    fun create_room_for_test(client: &signer): u64 {
        let now = timestamp::now_seconds();
        room::create_room(
            client,
            string::utf8(b"design"),
            b"task_hash_123",
            TEST_TASK_REWARD,
            now + 3600,       // deadline_submit: 1 hour
            now + 7200,       // deadline_jury_commit: 2 hours
            now + 10800,      // deadline_jury_reveal: 3 hours
        );
        1 // First room ID
    }

    // ============================================================
    // ROOM CREATION TESTS
    // ============================================================

    #[test(client = @0x123, framework = @0x1, aptosroom = @aptosroom)]
    /// Test successful room creation
    fun test_room_creation_success(client: &signer, framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);

        // Create funded client with keycard
        let client_addr = signer::address_of(client);
        account::create_account_for_test(client_addr);
        coin::register<AptosCoin>(client);
        aptos_coin::mint(framework, client_addr, TEST_TASK_REWARD * 2);
        keycard::mint(client);

        // Create room
        let room_id = create_room_for_test(client);

        // Assert room exists with correct state
        assert!(room::room_exists(room_id), 0);
        assert!(room::get_state(room_id) == constants::STATE_INIT(), 1);
        assert!(room::get_client(room_id) == client_addr, 2);
    }

    #[test(client = @0x123, framework = @0x1, aptosroom = @aptosroom)]
    #[expected_failure(abort_code = 103)] // E_KEYCARD_NOT_FOUND
    /// Test room creation without keycard rejected
    fun test_room_creation_without_keycard_rejected(client: &signer, framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);

        // Create funded client WITHOUT keycard
        let client_addr = signer::address_of(client);
        account::create_account_for_test(client_addr);
        coin::register<AptosCoin>(client);
        aptos_coin::mint(framework, client_addr, TEST_TASK_REWARD * 2);

        // Try to create room - should fail
        create_room_for_test(client);
    }

    #[test(client = @0x123, framework = @0x1, aptosroom = @aptosroom)]
    #[expected_failure] // Coin withdraw will fail with insufficient balance
    /// Test room creation with insufficient escrow rejected
    fun test_room_creation_insufficient_escrow_rejected(client: &signer, framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);

        // Create client with keycard but insufficient funds
        let client_addr = signer::address_of(client);
        account::create_account_for_test(client_addr);
        coin::register<AptosCoin>(client);
        aptos_coin::mint(framework, client_addr, 100); // Only 100 octas, need 1M
        keycard::mint(client);

        // Try to create room - should fail
        create_room_for_test(client);
    }

    // ============================================================
    // STATE TRANSITION TESTS (INVARIANT_ROOM_001)
    // ============================================================

    #[test(client = @0x123, framework = @0x1, aptosroom = @aptosroom)]
    /// Test valid transition INIT -> OPEN
    fun test_room_state_init_to_open(client: &signer, framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);

        let client_addr = signer::address_of(client);
        account::create_account_for_test(client_addr);
        coin::register<AptosCoin>(client);
        aptos_coin::mint(framework, client_addr, TEST_TASK_REWARD * 2);
        keycard::mint(client);

        let room_id = create_room_for_test(client);
        assert!(room::get_state(room_id) == constants::STATE_INIT(), 0);

        // Transition to OPEN
        room::open_room(client, room_id);
        assert!(room::get_state(room_id) == constants::STATE_OPEN(), 1);
    }

    #[test(client = @0x123, framework = @0x1, aptosroom = @aptosroom)]
    /// Test valid transition OPEN -> CLOSED
    fun test_room_state_open_to_closed(client: &signer, framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);

        let client_addr = signer::address_of(client);
        account::create_account_for_test(client_addr);
        coin::register<AptosCoin>(client);
        aptos_coin::mint(framework, client_addr, TEST_TASK_REWARD * 2);
        keycard::mint(client);

        let room_id = create_room_for_test(client);
        room::open_room(client, room_id);

        // Transition to CLOSED
        room::close_room(client, room_id);
        assert!(room::get_state(room_id) == constants::STATE_CLOSED(), 0);
    }

    #[test(client = @0x123, framework = @0x1, aptosroom = @aptosroom)]
    #[expected_failure(abort_code = 400)] // E_INVALID_STATE_TRANSITION
    /// Test invalid transition INIT -> JURY_ACTIVE rejected
    fun test_room_invalid_transition_rejected(client: &signer, framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);

        let client_addr = signer::address_of(client);
        account::create_account_for_test(client_addr);
        coin::register<AptosCoin>(client);
        aptos_coin::mint(framework, client_addr, TEST_TASK_REWARD * 2);
        keycard::mint(client);

        let room_id = create_room_for_test(client);

        // Try to start jury phase directly from INIT - should fail
        room::start_jury_phase(client, room_id);
    }

    #[test(client = @0x123, framework = @0x1, aptosroom = @aptosroom)]
    /// Test full state machine traversal
    fun test_room_full_state_machine(client: &signer, framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);

        let client_addr = signer::address_of(client);
        account::create_account_for_test(client_addr);
        coin::register<AptosCoin>(client);
        aptos_coin::mint(framework, client_addr, TEST_TASK_REWARD * 2);
        keycard::mint(client);

        let room_id = create_room_for_test(client);

        // INIT -> OPEN
        room::open_room(client, room_id);
        assert!(room::get_state(room_id) == constants::STATE_OPEN(), 0);

        // OPEN -> CLOSED
        room::close_room(client, room_id);
        assert!(room::get_state(room_id) == constants::STATE_CLOSED(), 1);

        // For CLOSED -> JURY_ACTIVE, need jury pool set
        // We test this transition works in integration tests
    }

    #[test(client = @0x123, framework = @0x1, aptosroom = @aptosroom)]
    #[expected_failure(abort_code = 400)] // E_INVALID_STATE_TRANSITION (checked before terminal)
    /// Test transition from SETTLED rejected (INVARIANT_ROOM_004)
    fun test_room_transition_from_settled_rejected(client: &signer, framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);

        let client_addr = signer::address_of(client);
        account::create_account_for_test(client_addr);
        coin::register<AptosCoin>(client);
        aptos_coin::mint(framework, client_addr, TEST_TASK_REWARD * 2);
        keycard::mint(client);

        let room_id = create_room_for_test(client);

        // Force room to SETTLED state using test helper
        room::test_set_state(room_id, constants::STATE_SETTLED());

        // Try any transition - should fail with E_STATE_IS_TERMINAL
        room::open_room(client, room_id);
    }

    // ============================================================
    // VAULT / ESCROW TESTS (INVARIANT_ROOM_003)
    // ============================================================

    #[test(client = @0x123, framework = @0x1, aptosroom = @aptosroom)]
    /// Test vault locked on creation
    fun test_vault_locked_on_creation(client: &signer, framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);

        let client_addr = signer::address_of(client);
        account::create_account_for_test(client_addr);
        coin::register<AptosCoin>(client);
        aptos_coin::mint(framework, client_addr, TEST_TASK_REWARD * 2);
        keycard::mint(client);

        let room_id = create_room_for_test(client);

        // Vault should be locked
        assert!(vault::is_locked(room_id), 0);
    }

    #[test(client = @0x123, framework = @0x1, aptosroom = @aptosroom)]
    #[expected_failure(abort_code = 300)] // E_VAULT_LOCKED
    /// Test vault withdraw before settle rejected
    fun test_vault_withdraw_before_settle_rejected(client: &signer, framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);

        let client_addr = signer::address_of(client);
        account::create_account_for_test(client_addr);
        coin::register<AptosCoin>(client);
        aptos_coin::mint(framework, client_addr, TEST_TASK_REWARD * 2);
        keycard::mint(client);

        let room_id = create_room_for_test(client);

        // Try to release funds while vault is locked - should fail
        vault::test_release_to_winner(room_id, client_addr, TEST_TASK_REWARD);
    }

    #[test(client = @0x123, framework = @0x1, aptosroom = @aptosroom)]
    /// Test vault unlocked after settle
    fun test_vault_unlocked_after_settle(client: &signer, framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);

        let client_addr = signer::address_of(client);
        account::create_account_for_test(client_addr);
        coin::register<AptosCoin>(client);
        aptos_coin::mint(framework, client_addr, TEST_TASK_REWARD * 2);
        keycard::mint(client);

        let room_id = create_room_for_test(client);

        // Unlock vault using test helper
        vault::test_unlock_vault(room_id);
        assert!(!vault::is_locked(room_id), 0);
    }

    // ============================================================
    // SUBMISSION TESTS (INVARIANT_SUBMISSION_001)
    // ============================================================

    #[test(client = @0x123, contributor = @0x456, framework = @0x1, aptosroom = @aptosroom)]
    /// Test successful submission
    fun test_submission_success(client: &signer, contributor: &signer, framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);

        // Setup client
        let client_addr = signer::address_of(client);
        account::create_account_for_test(client_addr);
        coin::register<AptosCoin>(client);
        aptos_coin::mint(framework, client_addr, TEST_TASK_REWARD * 2);
        keycard::mint(client);

        // Setup contributor
        let contrib_addr = signer::address_of(contributor);
        account::create_account_for_test(contrib_addr);
        keycard::mint(contributor);

        // Create and open room
        let room_id = create_room_for_test(client);
        room::open_room(client, room_id);

        // Submit entry
        room::submit_entry(contributor, room_id, b"submission_hash");
        assert!(room::has_submitted(room_id, contrib_addr), 0);
    }

    #[test(client = @0x123, contributor = @0x456, framework = @0x1, aptosroom = @aptosroom)]
    #[expected_failure(abort_code = 500)] // E_DUPLICATE_SUBMISSION
    /// Test duplicate submission rejected
    fun test_submission_duplicate_rejected(client: &signer, contributor: &signer, framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);

        let client_addr = signer::address_of(client);
        account::create_account_for_test(client_addr);
        coin::register<AptosCoin>(client);
        aptos_coin::mint(framework, client_addr, TEST_TASK_REWARD * 2);
        keycard::mint(client);

        let contrib_addr = signer::address_of(contributor);
        account::create_account_for_test(contrib_addr);
        keycard::mint(contributor);

        let room_id = create_room_for_test(client);
        room::open_room(client, room_id);

        // First submission succeeds
        room::submit_entry(contributor, room_id, b"submission_1");

        // Second submission should fail
        room::submit_entry(contributor, room_id, b"submission_2");
    }

    #[test(client = @0x123, contributor = @0x456, framework = @0x1, aptosroom = @aptosroom)]
    #[expected_failure(abort_code = 401)] // E_ROOM_NOT_OPEN
    /// Test submission in wrong state rejected
    fun test_submission_wrong_state_rejected(client: &signer, contributor: &signer, framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);

        let client_addr = signer::address_of(client);
        account::create_account_for_test(client_addr);
        coin::register<AptosCoin>(client);
        aptos_coin::mint(framework, client_addr, TEST_TASK_REWARD * 2);
        keycard::mint(client);

        let contrib_addr = signer::address_of(contributor);
        account::create_account_for_test(contrib_addr);
        keycard::mint(contributor);

        let room_id = create_room_for_test(client);
        // Room is in INIT state, NOT open

        // Try to submit - should fail
        room::submit_entry(contributor, room_id, b"submission");
    }

    #[test(client = @0x123, contributor = @0x456, framework = @0x1, aptosroom = @aptosroom)]
    #[expected_failure(abort_code = 501)] // E_DEADLINE_PASSED
    /// Test submission after deadline rejected
    fun test_submission_after_deadline_rejected(client: &signer, contributor: &signer, framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);

        let client_addr = signer::address_of(client);
        account::create_account_for_test(client_addr);
        coin::register<AptosCoin>(client);
        aptos_coin::mint(framework, client_addr, TEST_TASK_REWARD * 2);
        keycard::mint(client);

        let contrib_addr = signer::address_of(contributor);
        account::create_account_for_test(contrib_addr);
        keycard::mint(contributor);

        let room_id = create_room_for_test(client);
        room::open_room(client, room_id);

        // Fast forward past deadline (1 hour + 1 second)
        timestamp::fast_forward_seconds(3601);

        // Try to submit - should fail
        room::submit_entry(contributor, room_id, b"submission");
    }

    #[test(client = @0x123, contributor = @0x456, framework = @0x1, aptosroom = @aptosroom)]
    #[expected_failure(abort_code = 103)] // E_KEYCARD_NOT_FOUND
    /// Test submission without keycard rejected
    fun test_submission_without_keycard_rejected(client: &signer, contributor: &signer, framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);

        let client_addr = signer::address_of(client);
        account::create_account_for_test(client_addr);
        coin::register<AptosCoin>(client);
        aptos_coin::mint(framework, client_addr, TEST_TASK_REWARD * 2);
        keycard::mint(client);

        // Contributor WITHOUT keycard
        let contrib_addr = signer::address_of(contributor);
        account::create_account_for_test(contrib_addr);
        // No keycard::mint(contributor);

        let room_id = create_room_for_test(client);
        room::open_room(client, room_id);

        // Try to submit - should fail
        room::submit_entry(contributor, room_id, b"submission");
    }

    // ============================================================
    // CLIENT SCORE TESTS
    // ============================================================

    #[test(client = @0x123, contributor = @0x456, framework = @0x1, aptosroom = @aptosroom)]
    /// Test client can set score
    fun test_client_set_score_success(client: &signer, contributor: &signer, framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);

        let client_addr = signer::address_of(client);
        account::create_account_for_test(client_addr);
        coin::register<AptosCoin>(client);
        aptos_coin::mint(framework, client_addr, TEST_TASK_REWARD * 2);
        keycard::mint(client);

        let contrib_addr = signer::address_of(contributor);
        account::create_account_for_test(contrib_addr);
        keycard::mint(contributor);

        let room_id = create_room_for_test(client);
        room::open_room(client, room_id);
        room::submit_entry(contributor, room_id, b"submission");
        room::close_room(client, room_id);

        // Client sets score
        room::set_client_score(client, room_id, contrib_addr, 85);
    }

    #[test(other = @0x999, client = @0x123, contributor = @0x456, framework = @0x1, aptosroom = @aptosroom)]
    #[expected_failure(abort_code = 404)] // E_NOT_CLIENT
    /// Test non-client cannot set score
    fun test_non_client_set_score_rejected(other: &signer, client: &signer, contributor: &signer, framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);

        let client_addr = signer::address_of(client);
        account::create_account_for_test(client_addr);
        coin::register<AptosCoin>(client);
        aptos_coin::mint(framework, client_addr, TEST_TASK_REWARD * 2);
        keycard::mint(client);

        let contrib_addr = signer::address_of(contributor);
        account::create_account_for_test(contrib_addr);
        keycard::mint(contributor);

        let other_addr = signer::address_of(other);
        account::create_account_for_test(other_addr);

        let room_id = create_room_for_test(client);
        room::open_room(client, room_id);
        room::submit_entry(contributor, room_id, b"submission");
        room::close_room(client, room_id);

        // Non-client tries to set score - should fail
        room::set_client_score(other, room_id, contrib_addr, 85);
    }

    #[test(client = @0x123, contributor = @0x456, framework = @0x1, aptosroom = @aptosroom)]
    #[expected_failure(abort_code = 606)] // E_INVALID_SCORE
    /// Test score above max rejected
    fun test_client_score_above_max_rejected(client: &signer, contributor: &signer, framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);

        let client_addr = signer::address_of(client);
        account::create_account_for_test(client_addr);
        coin::register<AptosCoin>(client);
        aptos_coin::mint(framework, client_addr, TEST_TASK_REWARD * 2);
        keycard::mint(client);

        let contrib_addr = signer::address_of(contributor);
        account::create_account_for_test(contrib_addr);
        keycard::mint(contributor);

        let room_id = create_room_for_test(client);
        room::open_room(client, room_id);
        room::submit_entry(contributor, room_id, b"submission");
        room::close_room(client, room_id);

        // Try to set score above max (101 > 100) - should fail
        room::set_client_score(client, room_id, contrib_addr, 101);
    }
}
