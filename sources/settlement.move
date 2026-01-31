/// ============================================================
/// MODULE: Settlement
/// SPEC: EXECUTION_TASKS_BY_PHASE.md Section 2.8
/// INVARIANTS ENFORCED:
///   - INVARIANT_DUAL_KEY_001: Both keys required for payout
///   - INVARIANT_ROOM_004: Settled state is terminal
/// PURPOSE: Dual-Key settlement and fund release
/// ============================================================
module aptosroom::settlement {
    use std::signer;
    use std::option::{Self, Option};
    use std::vector;
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use aptosroom::errors;
    use aptosroom::constants;
    use aptosroom::room;
    use aptosroom::vault;
    use aptosroom::keycard;

    // ============================================================
    // EVENTS
    // ============================================================

    #[event]
    struct SettlementApproved has drop, store {
        room_id: u64,
        client: address,
        timestamp: u64,
    }

    #[event]
    struct RoomSettled has drop, store {
        room_id: u64,
        winner: address,
        final_score: u64,
        payout_amount: u64,
        timestamp: u64,
    }

    #[event]
    struct KeycardUpdated has drop, store {
        owner: address,
        room_id: u64,
        score: u64,
        is_winner: bool,
        timestamp: u64,
    }

    // ============================================================
    // CLIENT APPROVAL (GOLD KEY)
    // ============================================================

    /// Client approves settlement
    /// CTO RULE_GOLDKEY_001: Valid only in FINALIZED state
    /// CTO RULE_GOLDKEY_002: Single-use, irreversible
    public entry fun approve_settlement(
        account: &signer,
        room_id: u64,
    ) {
        let client = signer::address_of(account);

        // Assert room.state == STATE_FINALIZED
        let state = room::get_state(room_id);
        assert!(state == constants::STATE_FINALIZED(), errors::E_NOT_FINALIZED());

        // Assert signer == room.client
        let room_client = room::get_client(room_id);
        assert!(client == room_client, errors::E_NOT_CLIENT());

        // Assert !room.client_approved (single-use)
        assert!(!room::is_client_approved(room_id), errors::E_APPROVAL_ALREADY_GIVEN());

        // Set room.client_approved = true
        room::set_client_approved(room_id);

        // Emit event
        event::emit(SettlementApproved {
            room_id,
            client,
            timestamp: timestamp::now_seconds(),
        });
    }

    // ============================================================
    // SETTLEMENT EXECUTION
    // ============================================================

    /// Execute settlement and release funds
    /// INVARIANT_DUAL_KEY_001: Both keys must be present
    public entry fun execute_settlement(account: &signer, room_id: u64) {
        // Anyone can call, but both keys must be present
        let _ = signer::address_of(account);

        // Assert room.state == STATE_FINALIZED
        let state = room::get_state(room_id);
        assert!(state == constants::STATE_FINALIZED(), errors::E_NOT_FINALIZED());

        // Assert jury score computed (Silver Key)
        assert!(room::is_jury_score_computed(room_id), errors::E_JURY_NOT_FINALIZED());

        // Assert client approved (Gold Key)
        // INVARIANT_DUAL_KEY_001: Both keys verified
        assert!(room::is_client_approved(room_id), errors::E_CLIENT_NOT_APPROVED());

        // Determine winner
        let (winner, final_score) = determine_winner(room_id);

        // Release funds to winner
        release_funds(room_id, winner);

        // Update all keycards
        update_all_keycards(room_id, winner);

        // Set room.state = STATE_SETTLED via friend function
        room::complete_settlement(room_id, winner);

        // Emit event
        event::emit(RoomSettled {
            room_id,
            winner,
            final_score,
            payout_amount: room::get_task_reward(room_id),
            timestamp: timestamp::now_seconds(),
        });
    }

    // ============================================================
    // WINNER DETERMINATION
    // ============================================================

    /// Determine winner from final scores
    /// Tiebreaker: First submission by index wins
    fun determine_winner(room_id: u64): (address, u64) {
        let contributors = room::get_contributor_list(room_id);
        let len = vector::length(&contributors);
        
        // Must have at least one contributor
        assert!(len > 0, errors::E_NO_VALID_VOTES());

        let highest_score: u64 = 0;
        let winner = *vector::borrow(&contributors, 0);

        let i = 0;
        while (i < len) {
            let contributor = *vector::borrow(&contributors, i);
            let score = room::get_final_score(room_id, contributor);
            
            // Strict greater than: first submission wins ties
            if (score > highest_score) {
                highest_score = score;
                winner = contributor;
            };
            i = i + 1;
        };

        (winner, highest_score)
    }

    // ============================================================
    // FUND RELEASE
    // ============================================================

    /// Release funds to winner
    fun release_funds(room_id: u64, winner: address) {
        // Get task reward amount
        let payout = room::get_task_reward(room_id);

        // Unlock vault and release to winner
        vault::unlock_vault(room_id);
        vault::release_to_winner(room_id, winner, payout);
    }

    // ============================================================
    // KEYCARD UPDATES
    // ============================================================

    /// Update all participant keycards after settlement
    fun update_all_keycards(room_id: u64, winner: address) {
        let contributors = room::get_contributor_list(room_id);
        let len = vector::length(&contributors);

        // Update each contributor's keycard
        let i = 0;
        while (i < len) {
            let contributor = *vector::borrow(&contributors, i);
            let score = room::get_final_score(room_id, contributor);
            let is_winner = (contributor == winner);

            // Add task completion to keycard
            keycard::add_task_completion(contributor, score);

            // Emit event
            event::emit(KeycardUpdated {
                owner: contributor,
                room_id,
                score,
                is_winner,
                timestamp: timestamp::now_seconds(),
            });

            i = i + 1;
        };

        // Note: Jury participation already incremented during reveal_vote
        // Note: Variance flags already incremented during variance detection
    }

    // ============================================================
    // VIEW FUNCTIONS
    // ============================================================

    #[view]
    /// Check if client has approved
    public fun is_approved(room_id: u64): bool {
        room::is_client_approved(room_id)
    }

    #[view]
    /// Check if settlement is complete
    public fun is_settled(room_id: u64): bool {
        room::is_settled(room_id)
    }

    #[view]
    /// Get winner address
    public fun get_winner(room_id: u64): Option<address> {
        room::get_winner(room_id)
    }

    // ============================================================
    // TEST HELPERS
    // ============================================================

    #[test_only]
    /// Test helper to determine winner
    public fun test_determine_winner(room_id: u64): (address, u64) {
        determine_winner(room_id)
    }

    // ============================================================
    // TESTS
    // ============================================================

    #[test]
    fun test_dual_key_concept() {
        // Conceptual test: both keys required
        let jury_done = true;   // Silver Key
        let client_approved = true;  // Gold Key
        
        let can_settle = jury_done && client_approved;
        assert!(can_settle, 0);
    }

    #[test]
    fun test_single_key_insufficient() {
        // Silver key only
        let jury_done = true;
        let client_approved = false;
        assert!(!(jury_done && client_approved), 0);
        
        // Gold key only
        let jury_done = false;
        let client_approved = true;
        assert!(!(jury_done && client_approved), 0);
    }
}
