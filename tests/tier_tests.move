/// ============================================================
/// TEST MODULE: Tier System Tests
/// SPEC: TESTNET_TEST_PLAN.md Phase 8
/// PURPOSE: Integration tests for slot-limited tier voting system
/// ============================================================
#[test_only]
module aptosroom::tier_tests {
    use std::signer;
    use std::string;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::timestamp;
    use aptosroom::jury;
    use aptosroom::room;
    use aptosroom::vault;
    use aptosroom::keycard;
    use aptosroom::juror_registry;
    use aptosroom::constants;
    use aptosroom::aggregation;

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
        juror_registry::init_for_test(aptosroom);
    }

    /// Create a room with contributors in JURY_ACTIVE state
    fun setup_room_with_contributors(
        framework: &signer, 
        client: &signer, 
        contributors: vector<address>,
        jurors: vector<address>,
    ): u64 {
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

        // Add contributors
        let i = 0;
        let len = vector::length(&contributors);
        while (i < len) {
            let contributor = *vector::borrow(&contributors, i);
            room::test_add_contributor(room_id, contributor);
            i = i + 1;
        };

        // Set jury pool and state to JURY_ACTIVE
        room::test_set_state(room_id, constants::STATE_CLOSED());
        room::test_set_jury_pool(client, room_id, jurors);
        room::test_set_state(room_id, constants::STATE_JURY_ACTIVE());

        room_id
    }

    /// Create test salt
    fun test_salt(): vector<u8> {
        vector[1u8, 2u8, 3u8, 4u8, 5u8, 6u8, 7u8, 8u8]
    }

    /// Create test encrypted data (empty for tests)
    fun test_encrypted_data(): vector<u8> {
        vector::empty<u8>()
    }

    // ============================================================
    // TIER SLOT ALLOCATION TESTS
    // ============================================================

    #[test]
    /// Test tier slots for < 10 contributors
    fun test_tier_slots_low_contributors() {
        // With 5 contributors: A=1, B=2
        assert!(constants::get_tier_a_slots(5) == 1, 0);
        assert!(constants::get_tier_b_slots(5) == 2, 1);
        
        // With 9 contributors: still A=1, B=2
        assert!(constants::get_tier_a_slots(9) == 1, 2);
        assert!(constants::get_tier_b_slots(9) == 2, 3);
    }

    #[test]
    /// Test tier slots for 10-20 contributors
    fun test_tier_slots_mid_contributors() {
        // With 10 contributors: A=3, B=4
        assert!(constants::get_tier_a_slots(10) == 3, 0);
        assert!(constants::get_tier_b_slots(10) == 4, 1);
        
        // With 15 contributors: A=3, B=4
        assert!(constants::get_tier_a_slots(15) == 3, 2);
        assert!(constants::get_tier_b_slots(15) == 4, 3);
        
        // With 20 contributors: A=3, B=4
        assert!(constants::get_tier_a_slots(20) == 3, 4);
        assert!(constants::get_tier_b_slots(20) == 4, 5);
    }

    #[test]
    /// Test tier slots for > 20 contributors
    fun test_tier_slots_high_contributors() {
        // With 21 contributors: A=5, B=7
        assert!(constants::get_tier_a_slots(21) == 5, 0);
        assert!(constants::get_tier_b_slots(21) == 7, 1);
        
        // With 50 contributors: A=5, B=7
        assert!(constants::get_tier_a_slots(50) == 5, 2);
        assert!(constants::get_tier_b_slots(50) == 7, 3);
    }

    // ============================================================
    // TIER COMMIT TESTS
    // ============================================================

    #[test(juror = @0x789, client = @0x123, framework = @0x1, aptosroom = @aptosroom)]
    /// Test successful tier vote commit
    fun test_commit_tier_vote_success(
        juror: &signer, 
        client: &signer, 
        framework: &signer, 
        aptosroom: &signer
    ) {
        setup_test_env(framework, aptosroom);
        let juror_addr = signer::address_of(juror);
        account::create_account_for_test(juror_addr);
        keycard::mint(juror);

        // 5 contributors for simple slot testing (A=1, B=2)
        let contributors = vector[@0x101, @0x102, @0x103, @0x104, @0x105];
        let jurors = vector[juror_addr];
        let room_id = setup_room_with_contributors(framework, client, contributors, jurors);

        // Compute tier commit hash
        let tier_a = vector[@0x101]; // 1 address for Tier A
        let tier_b = vector[@0x102, @0x103]; // 2 addresses for Tier B
        let commit_hash = jury::test_compute_tier_commit_hash(tier_a, tier_b, test_salt());

        // Commit tier vote
        jury::commit_tier_vote(juror, room_id, commit_hash, test_encrypted_data());

        // Verify committed
        assert!(room::has_committed_tier_vote(room_id, juror_addr), 0);
    }

    #[test(juror = @0x789, client = @0x123, framework = @0x1, aptosroom = @aptosroom)]
    #[expected_failure(abort_code = 602)] // E_ALREADY_COMMITTED
    /// Test double tier commit rejected
    fun test_commit_tier_vote_double_rejected(
        juror: &signer, 
        client: &signer, 
        framework: &signer, 
        aptosroom: &signer
    ) {
        setup_test_env(framework, aptosroom);
        let juror_addr = signer::address_of(juror);
        account::create_account_for_test(juror_addr);
        keycard::mint(juror);

        let contributors = vector[@0x101, @0x102, @0x103, @0x104, @0x105];
        let jurors = vector[juror_addr];
        let room_id = setup_room_with_contributors(framework, client, contributors, jurors);

        let tier_a = vector[@0x101];
        let tier_b = vector[@0x102, @0x103];
        let commit_hash = jury::test_compute_tier_commit_hash(tier_a, tier_b, test_salt());

        // First commit
        jury::commit_tier_vote(juror, room_id, commit_hash, test_encrypted_data());
        
        // Second commit should fail
        jury::commit_tier_vote(juror, room_id, commit_hash, test_encrypted_data());
    }

    // ============================================================
    // TIER REVEAL TESTS
    // ============================================================

    #[test(juror = @0x789, client = @0x123, framework = @0x1, aptosroom = @aptosroom)]
    /// Test successful tier vote reveal
    fun test_reveal_tier_vote_success(
        juror: &signer, 
        client: &signer, 
        framework: &signer, 
        aptosroom: &signer
    ) {
        setup_test_env(framework, aptosroom);
        let juror_addr = signer::address_of(juror);
        account::create_account_for_test(juror_addr);
        keycard::mint(juror);

        let contributors = vector[@0x101, @0x102, @0x103, @0x104, @0x105];
        let jurors = vector[juror_addr];
        let room_id = setup_room_with_contributors(framework, client, contributors, jurors);

        let tier_a = vector[@0x101];
        let tier_b = vector[@0x102, @0x103];
        let commit_hash = jury::test_compute_tier_commit_hash(tier_a, tier_b, test_salt());

        // Commit
        jury::commit_tier_vote(juror, room_id, commit_hash, test_encrypted_data());

        // Transition to reveal phase
        room::test_set_state(room_id, constants::STATE_JURY_REVEAL());

        // Reveal
        jury::reveal_tier_vote(juror, room_id, tier_a, tier_b, test_salt());

        // Verify revealed
        assert!(room::has_revealed_tier_vote(room_id, juror_addr), 0);
        
        // Verify tier selections stored
        let stored_a = room::get_juror_tier_a_selections(room_id, juror_addr);
        let stored_b = room::get_juror_tier_b_selections(room_id, juror_addr);
        assert!(vector::length(&stored_a) == 1, 1);
        assert!(vector::length(&stored_b) == 2, 2);
    }

    #[test(juror = @0x789, client = @0x123, framework = @0x1, aptosroom = @aptosroom)]
    #[expected_failure(abort_code = 611)] // E_INVALID_TIER_A_COUNT
    /// Test wrong tier A count rejected
    fun test_reveal_tier_vote_wrong_a_count(
        juror: &signer, 
        client: &signer, 
        framework: &signer, 
        aptosroom: &signer
    ) {
        setup_test_env(framework, aptosroom);
        let juror_addr = signer::address_of(juror);
        account::create_account_for_test(juror_addr);
        keycard::mint(juror);

        let contributors = vector[@0x101, @0x102, @0x103, @0x104, @0x105];
        let jurors = vector[juror_addr];
        let room_id = setup_room_with_contributors(framework, client, contributors, jurors);

        // Wrong: 2 addresses for Tier A (should be 1)
        let tier_a = vector[@0x101, @0x102];
        let tier_b = vector[@0x103, @0x104];
        let commit_hash = jury::test_compute_tier_commit_hash(tier_a, tier_b, test_salt());

        jury::commit_tier_vote(juror, room_id, commit_hash, test_encrypted_data());
        room::test_set_state(room_id, constants::STATE_JURY_REVEAL());

        // Should fail with E_INVALID_TIER_A_COUNT
        jury::reveal_tier_vote(juror, room_id, tier_a, tier_b, test_salt());
    }

    #[test(juror = @0x789, client = @0x123, framework = @0x1, aptosroom = @aptosroom)]
    #[expected_failure(abort_code = 612)] // E_INVALID_TIER_B_COUNT
    /// Test wrong tier B count rejected
    fun test_reveal_tier_vote_wrong_b_count(
        juror: &signer, 
        client: &signer, 
        framework: &signer, 
        aptosroom: &signer
    ) {
        setup_test_env(framework, aptosroom);
        let juror_addr = signer::address_of(juror);
        account::create_account_for_test(juror_addr);
        keycard::mint(juror);

        let contributors = vector[@0x101, @0x102, @0x103, @0x104, @0x105];
        let jurors = vector[juror_addr];
        let room_id = setup_room_with_contributors(framework, client, contributors, jurors);

        // Wrong: 1 address for Tier B (should be 2)
        let tier_a = vector[@0x101];
        let tier_b = vector[@0x102];
        let commit_hash = jury::test_compute_tier_commit_hash(tier_a, tier_b, test_salt());

        jury::commit_tier_vote(juror, room_id, commit_hash, test_encrypted_data());
        room::test_set_state(room_id, constants::STATE_JURY_REVEAL());

        // Should fail with E_INVALID_TIER_B_COUNT
        jury::reveal_tier_vote(juror, room_id, tier_a, tier_b, test_salt());
    }

    #[test(juror = @0x789, client = @0x123, framework = @0x1, aptosroom = @aptosroom)]
    #[expected_failure(abort_code = 613)] // E_DUPLICATE_IN_TIERS
    /// Test duplicate address in A and B rejected
    fun test_reveal_tier_vote_duplicate_rejected(
        juror: &signer, 
        client: &signer, 
        framework: &signer, 
        aptosroom: &signer
    ) {
        setup_test_env(framework, aptosroom);
        let juror_addr = signer::address_of(juror);
        account::create_account_for_test(juror_addr);
        keycard::mint(juror);

        let contributors = vector[@0x101, @0x102, @0x103, @0x104, @0x105];
        let jurors = vector[juror_addr];
        let room_id = setup_room_with_contributors(framework, client, contributors, jurors);

        // Duplicate: @0x101 in both A and B
        let tier_a = vector[@0x101];
        let tier_b = vector[@0x101, @0x102];
        let commit_hash = jury::test_compute_tier_commit_hash(tier_a, tier_b, test_salt());

        jury::commit_tier_vote(juror, room_id, commit_hash, test_encrypted_data());
        room::test_set_state(room_id, constants::STATE_JURY_REVEAL());

        // Should fail with E_DUPLICATE_IN_TIERS
        jury::reveal_tier_vote(juror, room_id, tier_a, tier_b, test_salt());
    }

    #[test(juror = @0x789, client = @0x123, framework = @0x1, aptosroom = @aptosroom)]
    #[expected_failure(abort_code = 614)] // E_NOT_A_CONTRIBUTOR
    /// Test non-contributor selection rejected
    fun test_reveal_tier_vote_non_contributor_rejected(
        juror: &signer, 
        client: &signer, 
        framework: &signer, 
        aptosroom: &signer
    ) {
        setup_test_env(framework, aptosroom);
        let juror_addr = signer::address_of(juror);
        account::create_account_for_test(juror_addr);
        keycard::mint(juror);

        let contributors = vector[@0x101, @0x102, @0x103, @0x104, @0x105];
        let jurors = vector[juror_addr];
        let room_id = setup_room_with_contributors(framework, client, contributors, jurors);

        // Non-contributor @0x999
        let tier_a = vector[@0x999];
        let tier_b = vector[@0x102, @0x103];
        let commit_hash = jury::test_compute_tier_commit_hash(tier_a, tier_b, test_salt());

        jury::commit_tier_vote(juror, room_id, commit_hash, test_encrypted_data());
        room::test_set_state(room_id, constants::STATE_JURY_REVEAL());

        // Should fail with E_NOT_A_CONTRIBUTOR
        jury::reveal_tier_vote(juror, room_id, tier_a, tier_b, test_salt());
    }

    #[test(juror = @0x789, client = @0x123, framework = @0x1, aptosroom = @aptosroom)]
    #[expected_failure(abort_code = 605)] // E_HASH_MISMATCH
    /// Test tier reveal with wrong hash rejected
    fun test_reveal_tier_vote_hash_mismatch(
        juror: &signer, 
        client: &signer, 
        framework: &signer, 
        aptosroom: &signer
    ) {
        setup_test_env(framework, aptosroom);
        let juror_addr = signer::address_of(juror);
        account::create_account_for_test(juror_addr);
        keycard::mint(juror);

        let contributors = vector[@0x101, @0x102, @0x103, @0x104, @0x105];
        let jurors = vector[juror_addr];
        let room_id = setup_room_with_contributors(framework, client, contributors, jurors);

        // Commit with one set
        let tier_a = vector[@0x101];
        let tier_b = vector[@0x102, @0x103];
        let commit_hash = jury::test_compute_tier_commit_hash(tier_a, tier_b, test_salt());

        jury::commit_tier_vote(juror, room_id, commit_hash, test_encrypted_data());
        room::test_set_state(room_id, constants::STATE_JURY_REVEAL());

        // Reveal with different set - should fail
        let different_a = vector[@0x104];
        jury::reveal_tier_vote(juror, room_id, different_a, tier_b, test_salt());
    }

    // ============================================================
    // TIER FINAL SCORE CALCULATION TESTS
    // ============================================================

    #[test]
    /// Test tier final score calculation
    fun test_tier_final_score_calculation() {
        // Formula: (client_score * 60 / 100) + tier_score
        
        // Client=100, Tier A (40): (100 * 60 / 100) + 40 = 100
        let final = aggregation::calculate_tier_final_score(100, 40);
        assert!(final == 100, 0);
        
        // Client=100, Tier B (30): (100 * 60 / 100) + 30 = 90
        let final = aggregation::calculate_tier_final_score(100, 30);
        assert!(final == 90, 1);
        
        // Client=100, Tier C (20): (100 * 60 / 100) + 20 = 80
        let final = aggregation::calculate_tier_final_score(100, 20);
        assert!(final == 80, 2);
        
        // Client=90, Tier A: (90 * 60 / 100) + 40 = 94
        let final = aggregation::calculate_tier_final_score(90, 40);
        assert!(final == 94, 3);
        
        // Client=90, Tier B: (90 * 60 / 100) + 30 = 84
        let final = aggregation::calculate_tier_final_score(90, 30);
        assert!(final == 84, 4);
        
        // Client=90, Tier C: (90 * 60 / 100) + 20 = 74
        let final = aggregation::calculate_tier_final_score(90, 20);
        assert!(final == 74, 5);
        
        // Client=80, Tier A: (80 * 60 / 100) + 40 = 88
        let final = aggregation::calculate_tier_final_score(80, 40);
        assert!(final == 88, 6);
        
        // Client=50, Tier C: (50 * 60 / 100) + 20 = 50
        let final = aggregation::calculate_tier_final_score(50, 20);
        assert!(final == 50, 7);
    }

    #[test]
    /// Test tier to score conversion
    fun test_tier_to_score_conversion() {
        assert!(constants::tier_to_score(constants::TIER_A()) == 40, 0);
        assert!(constants::tier_to_score(constants::TIER_B()) == 30, 1);
        assert!(constants::tier_to_score(constants::TIER_C()) == 20, 2);
    }

    // ============================================================
    // TIER MAJORITY VOTE TESTS
    // ============================================================

    #[test]
    /// Test majority tier determination
    fun test_determine_majority_tier() {
        // 3 A, 1 B, 1 C -> A wins
        let majority = aggregation::determine_majority_tier(3, 1, 1);
        assert!(majority == constants::TIER_A(), 0);
        
        // 1 A, 3 B, 1 C -> B wins
        let majority = aggregation::determine_majority_tier(1, 3, 1);
        assert!(majority == constants::TIER_B(), 1);
        
        // 1 A, 1 B, 3 C -> C wins
        let majority = aggregation::determine_majority_tier(1, 1, 3);
        assert!(majority == constants::TIER_C(), 2);
        
        // Tie A=B=C -> A wins (higher tier)
        let majority = aggregation::determine_majority_tier(2, 2, 2);
        assert!(majority == constants::TIER_A(), 3);
        
        // Tie A=B -> A wins (higher tier)
        let majority = aggregation::determine_majority_tier(2, 2, 1);
        assert!(majority == constants::TIER_A(), 4);
        
        // Tie B=C -> B wins (higher tier)
        let majority = aggregation::determine_majority_tier(1, 2, 2);
        assert!(majority == constants::TIER_B(), 5);
    }

    // ============================================================
    // TIER VARIANCE TESTS
    // ============================================================

    #[test]
    /// Test tier absolute difference calculation
    fun test_tier_abs_diff() {
        use aptosroom::variance;
        
        // Same tier: distance = 0
        assert!(variance::tier_abs_diff(1, 1) == 0, 0);
        assert!(variance::tier_abs_diff(2, 2) == 0, 1);
        assert!(variance::tier_abs_diff(3, 3) == 0, 2);
        
        // One tier apart: distance = 1
        assert!(variance::tier_abs_diff(1, 2) == 1, 3);
        assert!(variance::tier_abs_diff(2, 1) == 1, 4);
        assert!(variance::tier_abs_diff(2, 3) == 1, 5);
        assert!(variance::tier_abs_diff(3, 2) == 1, 6);
        
        // Two tiers apart: distance = 2 (flagged!)
        assert!(variance::tier_abs_diff(1, 3) == 2, 7);
        assert!(variance::tier_abs_diff(3, 1) == 2, 8);
    }

    #[test]
    /// Test find majority tier
    fun test_find_majority_tier() {
        use aptosroom::variance;
        
        // All same tier
        let tiers = vector[1u8, 1u8, 1u8, 1u8, 1u8];
        assert!(variance::find_majority_tier(&tiers) == 1, 0);
        
        // Majority A
        let tiers = vector[1u8, 1u8, 1u8, 2u8, 3u8];
        assert!(variance::find_majority_tier(&tiers) == 1, 1);
        
        // Majority B
        let tiers = vector[1u8, 2u8, 2u8, 2u8, 3u8];
        assert!(variance::find_majority_tier(&tiers) == 2, 2);
        
        // Majority C
        let tiers = vector[1u8, 2u8, 3u8, 3u8, 3u8];
        assert!(variance::find_majority_tier(&tiers) == 3, 3);
    }

    // ============================================================
    // MULTI-JUROR TIER VOTING INTEGRATION TESTS
    // ============================================================

    #[test(juror1 = @0x789, juror2 = @0x790, juror3 = @0x791, client = @0x123, framework = @0x1, aptosroom = @aptosroom)]
    /// Test multi-juror tier voting with majority consensus
    fun test_multi_juror_tier_voting(
        juror1: &signer,
        juror2: &signer,
        juror3: &signer,
        client: &signer,
        framework: &signer,
        aptosroom: &signer
    ) {
        setup_test_env(framework, aptosroom);
        
        // Setup jurors
        let juror1_addr = signer::address_of(juror1);
        let juror2_addr = signer::address_of(juror2);
        let juror3_addr = signer::address_of(juror3);
        
        account::create_account_for_test(juror1_addr);
        account::create_account_for_test(juror2_addr);
        account::create_account_for_test(juror3_addr);
        keycard::mint(juror1);
        keycard::mint(juror2);
        keycard::mint(juror3);

        // 5 contributors for slot testing (A=1, B=2)
        let contributors = vector[@0x101, @0x102, @0x103, @0x104, @0x105];
        let jurors = vector[juror1_addr, juror2_addr, juror3_addr];
        let room_id = setup_room_with_contributors(framework, client, contributors, jurors);

        // All jurors vote: Tier A = @0x101, Tier B = @0x102, @0x103
        let tier_a = vector[@0x101];
        let tier_b = vector[@0x102, @0x103];
        let salt1 = vector[1u8, 1u8, 1u8, 1u8];
        let salt2 = vector[2u8, 2u8, 2u8, 2u8];
        let salt3 = vector[3u8, 3u8, 3u8, 3u8];

        // Juror 1 commits
        let hash1 = jury::test_compute_tier_commit_hash(tier_a, tier_b, salt1);
        jury::commit_tier_vote(juror1, room_id, hash1, test_encrypted_data());
        
        // Juror 2 commits same choice
        let hash2 = jury::test_compute_tier_commit_hash(tier_a, tier_b, salt2);
        jury::commit_tier_vote(juror2, room_id, hash2, test_encrypted_data());
        
        // Juror 3 commits same choice
        let hash3 = jury::test_compute_tier_commit_hash(tier_a, tier_b, salt3);
        jury::commit_tier_vote(juror3, room_id, hash3, test_encrypted_data());

        // All committed
        assert!(room::has_committed_tier_vote(room_id, juror1_addr), 0);
        assert!(room::has_committed_tier_vote(room_id, juror2_addr), 1);
        assert!(room::has_committed_tier_vote(room_id, juror3_addr), 2);

        // Transition to reveal
        room::test_set_state(room_id, constants::STATE_JURY_REVEAL());

        // All reveal
        jury::reveal_tier_vote(juror1, room_id, tier_a, tier_b, salt1);
        jury::reveal_tier_vote(juror2, room_id, tier_a, tier_b, salt2);
        jury::reveal_tier_vote(juror3, room_id, tier_a, tier_b, salt3);

        // All revealed
        assert!(room::has_revealed_tier_vote(room_id, juror1_addr), 3);
        assert!(room::has_revealed_tier_vote(room_id, juror2_addr), 4);
        assert!(room::has_revealed_tier_vote(room_id, juror3_addr), 5);
    }

    #[test(juror1 = @0x789, juror2 = @0x790, juror3 = @0x791, client = @0x123, framework = @0x1, aptosroom = @aptosroom)]
    /// Test tier aggregation with unanimous vote
    fun test_tier_aggregation_unanimous(
        juror1: &signer,
        juror2: &signer,
        juror3: &signer,
        client: &signer,
        framework: &signer,
        aptosroom: &signer
    ) {
        setup_test_env(framework, aptosroom);
        
        let juror1_addr = signer::address_of(juror1);
        let juror2_addr = signer::address_of(juror2);
        let juror3_addr = signer::address_of(juror3);
        
        account::create_account_for_test(juror1_addr);
        account::create_account_for_test(juror2_addr);
        account::create_account_for_test(juror3_addr);
        keycard::mint(juror1);
        keycard::mint(juror2);
        keycard::mint(juror3);

        let contributors = vector[@0x101, @0x102, @0x103, @0x104, @0x105];
        let jurors = vector[juror1_addr, juror2_addr, juror3_addr];
        let room_id = setup_room_with_contributors(framework, client, contributors, jurors);

        // All vote @0x101 for Tier A, @0x102/@0x103 for Tier B
        let tier_a = vector[@0x101];
        let tier_b = vector[@0x102, @0x103];
        let salt1 = vector[1u8, 1u8, 1u8, 1u8];
        let salt2 = vector[2u8, 2u8, 2u8, 2u8];
        let salt3 = vector[3u8, 3u8, 3u8, 3u8];

        // Commit and reveal
        let hash1 = jury::test_compute_tier_commit_hash(tier_a, tier_b, salt1);
        let hash2 = jury::test_compute_tier_commit_hash(tier_a, tier_b, salt2);
        let hash3 = jury::test_compute_tier_commit_hash(tier_a, tier_b, salt3);
        
        jury::commit_tier_vote(juror1, room_id, hash1, test_encrypted_data());
        jury::commit_tier_vote(juror2, room_id, hash2, test_encrypted_data());
        jury::commit_tier_vote(juror3, room_id, hash3, test_encrypted_data());

        room::test_set_state(room_id, constants::STATE_JURY_REVEAL());

        jury::reveal_tier_vote(juror1, room_id, tier_a, tier_b, salt1);
        jury::reveal_tier_vote(juror2, room_id, tier_a, tier_b, salt2);
        jury::reveal_tier_vote(juror3, room_id, tier_a, tier_b, salt3);

        // Aggregate tier votes
        aggregation::aggregate_tier_votes(room_id);

        // Verify tiers computed
        assert!(room::are_tiers_computed(room_id), 0);

        // Verify contributor tiers
        // @0x101 should be Tier A (all 3 voted A)
        assert!(room::get_contributor_tier(room_id, @0x101) == constants::TIER_A(), 1);
        // @0x102 should be Tier B (all 3 voted B)
        assert!(room::get_contributor_tier(room_id, @0x102) == constants::TIER_B(), 2);
        // @0x103 should be Tier B (all 3 voted B)
        assert!(room::get_contributor_tier(room_id, @0x103) == constants::TIER_B(), 3);
        // @0x104 should be Tier C (not in A or B)
        assert!(room::get_contributor_tier(room_id, @0x104) == constants::TIER_C(), 4);
        // @0x105 should be Tier C (not in A or B)
        assert!(room::get_contributor_tier(room_id, @0x105) == constants::TIER_C(), 5);

        // Verify jury scores match tier
        assert!(room::get_contributor_jury_score(room_id, @0x101) == 40, 6); // Tier A
        assert!(room::get_contributor_jury_score(room_id, @0x102) == 30, 7); // Tier B
        assert!(room::get_contributor_jury_score(room_id, @0x104) == 20, 8); // Tier C
    }

    #[test(juror1 = @0x789, juror2 = @0x790, juror3 = @0x791, client = @0x123, framework = @0x1, aptosroom = @aptosroom)]
    /// Test tier aggregation with split votes (majority wins)
    fun test_tier_aggregation_split_vote(
        juror1: &signer,
        juror2: &signer,
        juror3: &signer,
        client: &signer,
        framework: &signer,
        aptosroom: &signer
    ) {
        setup_test_env(framework, aptosroom);
        
        let juror1_addr = signer::address_of(juror1);
        let juror2_addr = signer::address_of(juror2);
        let juror3_addr = signer::address_of(juror3);
        
        account::create_account_for_test(juror1_addr);
        account::create_account_for_test(juror2_addr);
        account::create_account_for_test(juror3_addr);
        keycard::mint(juror1);
        keycard::mint(juror2);
        keycard::mint(juror3);

        let contributors = vector[@0x101, @0x102, @0x103, @0x104, @0x105];
        let jurors = vector[juror1_addr, juror2_addr, juror3_addr];
        let room_id = setup_room_with_contributors(framework, client, contributors, jurors);

        // Split votes for @0x104:
        // Juror1: @0x101=A, @0x102,@0x103=B -> @0x104=C
        // Juror2: @0x101=A, @0x104,@0x105=B -> @0x104=B (minority)
        // Juror3: @0x101=A, @0x102,@0x103=B -> @0x104=C
        // Result: @0x104 should be C (2 votes) vs B (1 vote)

        let tier_a_1 = vector[@0x101];
        let tier_b_1 = vector[@0x102, @0x103]; // @0x104 default C
        let salt1 = vector[1u8, 1u8, 1u8, 1u8];

        let tier_a_2 = vector[@0x101];
        let tier_b_2 = vector[@0x104, @0x105]; // @0x104 explicitly B
        let salt2 = vector[2u8, 2u8, 2u8, 2u8];

        let tier_a_3 = vector[@0x101];
        let tier_b_3 = vector[@0x102, @0x103]; // @0x104 default C
        let salt3 = vector[3u8, 3u8, 3u8, 3u8];

        // Commit
        let hash1 = jury::test_compute_tier_commit_hash(tier_a_1, tier_b_1, salt1);
        let hash2 = jury::test_compute_tier_commit_hash(tier_a_2, tier_b_2, salt2);
        let hash3 = jury::test_compute_tier_commit_hash(tier_a_3, tier_b_3, salt3);
        
        jury::commit_tier_vote(juror1, room_id, hash1, test_encrypted_data());
        jury::commit_tier_vote(juror2, room_id, hash2, test_encrypted_data());
        jury::commit_tier_vote(juror3, room_id, hash3, test_encrypted_data());

        // Reveal
        room::test_set_state(room_id, constants::STATE_JURY_REVEAL());
        jury::reveal_tier_vote(juror1, room_id, tier_a_1, tier_b_1, salt1);
        jury::reveal_tier_vote(juror2, room_id, tier_a_2, tier_b_2, salt2);
        jury::reveal_tier_vote(juror3, room_id, tier_a_3, tier_b_3, salt3);

        // Aggregate
        aggregation::aggregate_tier_votes(room_id);

        // @0x101: A (unanimous)
        assert!(room::get_contributor_tier(room_id, @0x101) == constants::TIER_A(), 0);
        
        // @0x102: B (2 votes) vs C (1 vote) -> B
        assert!(room::get_contributor_tier(room_id, @0x102) == constants::TIER_B(), 1);
        
        // @0x104: C (2 votes) vs B (1 vote) -> C
        assert!(room::get_contributor_tier(room_id, @0x104) == constants::TIER_C(), 2);
        
        // @0x105: B (1 vote) vs C (2 votes) -> C
        assert!(room::get_contributor_tier(room_id, @0x105) == constants::TIER_C(), 3);
    }

    #[test(juror1 = @0x789, juror2 = @0x790, juror3 = @0x791, client = @0x123, framework = @0x1, aptosroom = @aptosroom)]
    /// Test tier final score processing after aggregation
    fun test_tier_final_score_processing(
        juror1: &signer,
        juror2: &signer,
        juror3: &signer,
        client: &signer,
        framework: &signer,
        aptosroom: &signer
    ) {
        setup_test_env(framework, aptosroom);
        
        let juror1_addr = signer::address_of(juror1);
        let juror2_addr = signer::address_of(juror2);
        let juror3_addr = signer::address_of(juror3);
        let client_addr = signer::address_of(client);
        
        account::create_account_for_test(juror1_addr);
        account::create_account_for_test(juror2_addr);
        account::create_account_for_test(juror3_addr);
        keycard::mint(juror1);
        keycard::mint(juror2);
        keycard::mint(juror3);

        let contributors = vector[@0x101, @0x102, @0x103, @0x104, @0x105];
        let jurors = vector[juror1_addr, juror2_addr, juror3_addr];
        let room_id = setup_room_with_contributors(framework, client, contributors, jurors);

        // All give same tier votes
        let tier_a = vector[@0x101];
        let tier_b = vector[@0x102, @0x103];
        let salt1 = vector[1u8, 1u8, 1u8, 1u8];
        let salt2 = vector[2u8, 2u8, 2u8, 2u8];
        let salt3 = vector[3u8, 3u8, 3u8, 3u8];

        let hash1 = jury::test_compute_tier_commit_hash(tier_a, tier_b, salt1);
        let hash2 = jury::test_compute_tier_commit_hash(tier_a, tier_b, salt2);
        let hash3 = jury::test_compute_tier_commit_hash(tier_a, tier_b, salt3);
        
        jury::commit_tier_vote(juror1, room_id, hash1, test_encrypted_data());
        jury::commit_tier_vote(juror2, room_id, hash2, test_encrypted_data());
        jury::commit_tier_vote(juror3, room_id, hash3, test_encrypted_data());

        room::test_set_state(room_id, constants::STATE_JURY_REVEAL());
        jury::reveal_tier_vote(juror1, room_id, tier_a, tier_b, salt1);
        jury::reveal_tier_vote(juror2, room_id, tier_a, tier_b, salt2);
        jury::reveal_tier_vote(juror3, room_id, tier_a, tier_b, salt3);

        // Aggregate tier votes
        aggregation::aggregate_tier_votes(room_id);

        // Set client scores
        room::test_set_client_score(room_id, @0x101, 100); // Full marks
        room::test_set_client_score(room_id, @0x102, 90);
        room::test_set_client_score(room_id, @0x103, 80);
        room::test_set_client_score(room_id, @0x104, 70);
        room::test_set_client_score(room_id, @0x105, 60);

        // Process tier-based final scores
        aggregation::process_tier_final_scores(room_id);

        // Verify final scores:
        // @0x101: (100 * 60 / 100) + 40 = 100
        assert!(room::get_final_score(room_id, @0x101) == 100, 0);
        
        // @0x102: (90 * 60 / 100) + 30 = 84
        assert!(room::get_final_score(room_id, @0x102) == 84, 1);
        
        // @0x103: (80 * 60 / 100) + 30 = 78
        assert!(room::get_final_score(room_id, @0x103) == 78, 2);
        
        // @0x104: (70 * 60 / 100) + 20 = 62
        assert!(room::get_final_score(room_id, @0x104) == 62, 3);
        
        // @0x105: (60 * 60 / 100) + 20 = 56
        assert!(room::get_final_score(room_id, @0x105) == 56, 4);
    }

    #[test]
    /// Test tier boundary edge cases
    fun test_tier_slot_edge_cases() {
        // Exactly at boundary: 10 contributors
        assert!(constants::get_tier_a_slots(10) == 3, 0);
        assert!(constants::get_tier_b_slots(10) == 4, 1);
        
        // Exactly at boundary: 20 contributors
        assert!(constants::get_tier_a_slots(20) == 3, 2);
        assert!(constants::get_tier_b_slots(20) == 4, 3);
        
        // Edge: 1 contributor
        assert!(constants::get_tier_a_slots(1) == 1, 4);
        assert!(constants::get_tier_b_slots(1) == 0, 5);
        
        // Edge: 0 contributors (should still return minimum slots)
        assert!(constants::get_tier_a_slots(0) == 1, 6);
        assert!(constants::get_tier_b_slots(0) == 2, 7);
    }
}
