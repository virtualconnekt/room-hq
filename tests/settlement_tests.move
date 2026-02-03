/// ============================================================
/// TEST MODULE: Settlement Tests
/// SPEC: TEST_PLAN.md Section 5.5
/// PURPOSE: Unit tests for Dual-Key settlement
/// ============================================================
#[test_only]
module aptosroom::settlement_tests {
    use std::signer;
    use std::string;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::timestamp;
    use aptosroom::settlement;
    use aptosroom::room;
    use aptosroom::vault;
    use aptosroom::keycard;
    use aptosroom::constants;

    // ============================================================
    // TEST CONSTANTS
    // ============================================================

    const TEST_TASK_REWARD: u64 = 1000000;

    // ============================================================
    // TEST SETUP HELPERS
    // ============================================================

    /// Setup test environment with all modules
    fun setup_test_env(framework: &signer, aptosroom: &signer) {
        timestamp::set_time_has_started_for_testing(framework);
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(framework);
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
        keycard::init_for_test(aptosroom);
        vault::init_for_test(aptosroom);
        room::init_for_test(aptosroom);
    }

    /// Create a room in FINALIZED state for settlement tests
    fun setup_finalized_room(framework: &signer, client: &signer, contributor_addr: address): u64 {
        let client_addr = signer::address_of(client);
        account::create_account_for_test(client_addr);
        coin::register<AptosCoin>(client);
        aptos_coin::mint(framework, client_addr, TEST_TASK_REWARD * 2);
        keycard::mint(client);

        // Create room
        let now = timestamp::now_seconds();
        room::create_room(
            client,
            string::utf8(b"design"),
            b"task_hash",
            TEST_TASK_REWARD,
            now + 3600,
            now + 7200,
            now + 10800,
        );
        let room_id = 1;

        // Add contributor to simulate submission
        room::test_add_contributor(room_id, contributor_addr);

        // Set jury score as computed (Silver Key)
        room::test_set_jury_score(room_id, 85);

        // Set final score for contributor
        room::test_set_final_score(room_id, contributor_addr, 85);

        // Set state to FINALIZED
        room::test_set_state(room_id, constants::STATE_FINALIZED());

        room_id
    }

    // ============================================================
    // CLIENT APPROVAL TESTS (GOLD KEY)
    // ============================================================

    #[test(client = @0x123, contributor = @0x456, framework = @0x1, aptosroom = @aptosroom)]
    /// Test successful approval
    fun test_approve_settlement_success(client: &signer, contributor: &signer, framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);
        let contributor_addr = signer::address_of(contributor);
        account::create_account_for_test(contributor_addr);
        keycard::mint(contributor);

        let room_id = setup_finalized_room(framework, client, contributor_addr);

        // Client approves settlement
        settlement::approve_settlement(client, room_id);

        // Verify approval
        assert!(settlement::is_approved(room_id), 0);
    }

    #[test(other = @0x999, client = @0x123, contributor = @0x456, framework = @0x1, aptosroom = @aptosroom)]
    #[expected_failure(abort_code = 404)] // E_NOT_CLIENT
    /// Test non-client approval rejected
    fun test_approve_non_client_rejected(other: &signer, client: &signer, contributor: &signer, framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);
        let contributor_addr = signer::address_of(contributor);
        account::create_account_for_test(contributor_addr);
        keycard::mint(contributor);

        let room_id = setup_finalized_room(framework, client, contributor_addr);

        // Non-client tries to approve - should fail
        settlement::approve_settlement(other, room_id);
    }

    #[test(client = @0x123, contributor = @0x456, framework = @0x1, aptosroom = @aptosroom)]
    #[expected_failure(abort_code = 703)] // E_APPROVAL_ALREADY_GIVEN
    /// Test double approval rejected
    fun test_approve_double_approval_rejected(client: &signer, contributor: &signer, framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);
        let contributor_addr = signer::address_of(contributor);
        account::create_account_for_test(contributor_addr);
        keycard::mint(contributor);

        let room_id = setup_finalized_room(framework, client, contributor_addr);

        // First approval succeeds
        settlement::approve_settlement(client, room_id);

        // Second approval should fail
        settlement::approve_settlement(client, room_id);
    }

    #[test(client = @0x123, contributor = @0x456, framework = @0x1, aptosroom = @aptosroom)]
    #[expected_failure(abort_code = 700)] // E_NOT_FINALIZED
    /// Test approval in wrong state rejected
    fun test_approve_wrong_state_rejected(client: &signer, contributor: &signer, framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);
        let contributor_addr = signer::address_of(contributor);
        account::create_account_for_test(contributor_addr);
        keycard::mint(contributor);

        let room_id = setup_finalized_room(framework, client, contributor_addr);

        // Change state to something other than FINALIZED
        room::test_set_state(room_id, constants::STATE_OPEN());

        // Try to approve in wrong state - should fail
        settlement::approve_settlement(client, room_id);
    }

    // ============================================================
    // DUAL-KEY TESTS (INVARIANT_DUAL_KEY_001)
    // ============================================================

    #[test(client = @0x123, contributor = @0x456, framework = @0x1, aptosroom = @aptosroom)]
    /// Test settlement with both keys succeeds
    fun test_settlement_both_keys_required(client: &signer, contributor: &signer, framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);
        let contributor_addr = signer::address_of(contributor);
        account::create_account_for_test(contributor_addr);
        coin::register<AptosCoin>(contributor);
        keycard::mint(contributor);

        let room_id = setup_finalized_room(framework, client, contributor_addr);

        // Gold Key: Client approves
        settlement::approve_settlement(client, room_id);

        // Execute settlement (both keys present)
        settlement::execute_settlement(client, room_id);

        // Verify room is SETTLED
        assert!(settlement::is_settled(room_id), 0);
    }

    #[test(client = @0x123, contributor = @0x456, framework = @0x1, aptosroom = @aptosroom)]
    #[expected_failure(abort_code = 702)] // E_CLIENT_NOT_APPROVED
    /// Test settlement without client approval fails
    fun test_settlement_without_approval_rejected(client: &signer, contributor: &signer, framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);
        let contributor_addr = signer::address_of(contributor);
        account::create_account_for_test(contributor_addr);
        coin::register<AptosCoin>(contributor);
        keycard::mint(contributor);

        let room_id = setup_finalized_room(framework, client, contributor_addr);

        // Silver Key present (jury_score_computed), but NO Gold Key (client approval)
        // Try to execute settlement - should fail
        settlement::execute_settlement(client, room_id);
    }

    #[test(client = @0x123, contributor = @0x456, framework = @0x1, aptosroom = @aptosroom)]
    #[expected_failure(abort_code = 701)] // E_JURY_NOT_FINALIZED
    /// Test settlement without jury score fails
    fun test_settlement_without_jury_score_rejected(client: &signer, contributor: &signer, framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);
        let contributor_addr = signer::address_of(contributor);
        account::create_account_for_test(contributor_addr);
        keycard::mint(contributor);

        // Create room manually without setting jury score
        let client_addr = signer::address_of(client);
        account::create_account_for_test(client_addr);
        coin::register<AptosCoin>(client);
        aptos_coin::mint(framework, client_addr, TEST_TASK_REWARD * 2);
        keycard::mint(client);

        let now = timestamp::now_seconds();
        room::create_room(
            client,
            string::utf8(b"design"),
            b"task_hash",
            TEST_TASK_REWARD,
            now + 3600,
            now + 7200,
            now + 10800,
        );
        let room_id = 1;

        // Set to FINALIZED but DON'T set jury score (Silver Key missing)
        room::test_set_state(room_id, constants::STATE_FINALIZED());

        // Gold Key: Client approves
        settlement::approve_settlement(client, room_id);

        // Try to execute - should fail because jury_score_computed is false
        settlement::execute_settlement(client, room_id);
    }

    // ============================================================
    // PAYOUT TESTS
    // ============================================================

    #[test(client = @0x123, winner = @0x456, framework = @0x1, aptosroom = @aptosroom)]
    /// Test winner receives full payout
    fun test_winner_receives_full_payout(client: &signer, winner: &signer, framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);
        let winner_addr = signer::address_of(winner);
        account::create_account_for_test(winner_addr);
        coin::register<AptosCoin>(winner);
        keycard::mint(winner);

        let room_id = setup_finalized_room(framework, client, winner_addr);

        let balance_before = coin::balance<AptosCoin>(winner_addr);

        // Complete settlement
        settlement::approve_settlement(client, room_id);
        settlement::execute_settlement(client, room_id);

        let balance_after = coin::balance<AptosCoin>(winner_addr);
        assert!(balance_after == balance_before + TEST_TASK_REWARD, 0);
    }

    #[test(client = @0x123, winner = @0x456, framework = @0x1, aptosroom = @aptosroom)]
    /// Test winner keycard updated
    fun test_winner_keycard_updated(client: &signer, winner: &signer, framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);
        let winner_addr = signer::address_of(winner);
        account::create_account_for_test(winner_addr);
        coin::register<AptosCoin>(winner);
        keycard::mint(winner);

        let tasks_before = keycard::get_tasks_completed(winner_addr);

        let room_id = setup_finalized_room(framework, client, winner_addr);

        settlement::approve_settlement(client, room_id);
        settlement::execute_settlement(client, room_id);

        let tasks_after = keycard::get_tasks_completed(winner_addr);
        assert!(tasks_after == tasks_before + 1, 0);
    }

    #[test(client = @0x123, winner = @0x456, loser = @0x789, framework = @0x1, aptosroom = @aptosroom)]
    /// Test loser keycards updated
    fun test_loser_keycards_updated(client: &signer, winner: &signer, loser: &signer, framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);

        // Setup winner
        let winner_addr = signer::address_of(winner);
        account::create_account_for_test(winner_addr);
        coin::register<AptosCoin>(winner);
        keycard::mint(winner);

        // Setup loser
        let loser_addr = signer::address_of(loser);
        account::create_account_for_test(loser_addr);
        keycard::mint(loser);

        // Create room with both contributors
        let room_id = setup_finalized_room(framework, client, winner_addr);
        room::test_add_contributor(room_id, loser_addr);
        room::test_set_final_score(room_id, loser_addr, 60); // Lower score than winner

        let loser_tasks_before = keycard::get_tasks_completed(loser_addr);

        settlement::approve_settlement(client, room_id);
        settlement::execute_settlement(client, room_id);

        // Loser keycard should also be updated (participated)
        let loser_tasks_after = keycard::get_tasks_completed(loser_addr);
        assert!(loser_tasks_after == loser_tasks_before + 1, 0);
    }

    #[test(client = @0x123, contributor = @0x456, framework = @0x1, aptosroom = @aptosroom)]
    /// Test funds released exactly once
    fun test_funds_released_exactly_once(client: &signer, contributor: &signer, framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);
        let contributor_addr = signer::address_of(contributor);
        account::create_account_for_test(contributor_addr);
        coin::register<AptosCoin>(contributor);
        keycard::mint(contributor);

        let room_id = setup_finalized_room(framework, client, contributor_addr);

        settlement::approve_settlement(client, room_id);
        settlement::execute_settlement(client, room_id);

        // Vault should be empty
        assert!(vault::get_balance(room_id) == 0, 0);

        // Room should be in SETTLED state
        assert!(settlement::is_settled(room_id), 1);
    }

    #[test(client = @0x123, contributor = @0x456, framework = @0x1, aptosroom = @aptosroom)]
    /// Test vault unlocked after settle
    fun test_vault_unlocked_after_settle(client: &signer, contributor: &signer, framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);
        let contributor_addr = signer::address_of(contributor);
        account::create_account_for_test(contributor_addr);
        coin::register<AptosCoin>(contributor);
        keycard::mint(contributor);

        let room_id = setup_finalized_room(framework, client, contributor_addr);

        // Vault should be locked before settlement
        assert!(vault::is_locked(room_id), 0);

        settlement::approve_settlement(client, room_id);
        settlement::execute_settlement(client, room_id);

        // Vault should be unlocked after settlement
        assert!(!vault::is_locked(room_id), 1);
    }

    // ============================================================
    // STATE FINALITY TESTS (INVARIANT_ROOM_004)
    // ============================================================

    #[test(client = @0x123, contributor = @0x456, framework = @0x1, aptosroom = @aptosroom)]
    /// Test settled state is final
    fun test_state_settled_is_final(client: &signer, contributor: &signer, framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);
        let contributor_addr = signer::address_of(contributor);
        account::create_account_for_test(contributor_addr);
        coin::register<AptosCoin>(contributor);
        keycard::mint(contributor);

        let room_id = setup_finalized_room(framework, client, contributor_addr);

        settlement::approve_settlement(client, room_id);
        settlement::execute_settlement(client, room_id);

        // State should be SETTLED (terminal)
        assert!(room::get_state(room_id) == constants::STATE_SETTLED(), 0);
    }

    // ============================================================
    // ZERO VOTES TESTS
    // ============================================================

    #[test(client = @0x123, framework = @0x1, aptosroom = @aptosroom)]
    /// Test zero valid votes triggers refund (placeholder)
    fun test_zero_valid_votes_refund(client: &signer, framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);
        // Zero votes handling is complex - this is a placeholder
        // Full implementation in Phase 3
    }

    // ============================================================
    // WINNER DETERMINATION TESTS
    // ============================================================

    #[test(framework = @0x1, aptosroom = @aptosroom)]
    /// Test winner is highest score (placeholder)
    fun test_winner_is_highest_score(framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);
        // Winner determination logic tested in full integration tests
    }

    #[test(framework = @0x1, aptosroom = @aptosroom)]
    /// Test tie goes to first submission (placeholder)
    fun test_tie_first_submission_wins(framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);
        // Tie-breaking logic tested in full integration tests
    }

    #[test(framework = @0x1, aptosroom = @aptosroom)]
    /// Test single contributor is winner (placeholder)
    fun test_single_contributor_wins(framework: &signer, aptosroom: &signer) {
        setup_test_env(framework, aptosroom);
        // Single contributor case tested above in payout tests
    }
}
