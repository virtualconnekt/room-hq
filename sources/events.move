/// ============================================================
/// MODULE: Events
/// SPEC: IMPLEMENTATION_PLAN_FULL.md Day 0-1
/// PURPOSE: All protocol events for off-chain indexing
/// ============================================================
module aptosroom::events {
    use std::string::String;
    use aptos_framework::event;

    // ============================================================
    // KEYCARD EVENTS
    // ============================================================

    #[event]
    /// Emitted when a new keycard is minted
    struct KeycardMinted has drop, store {
        owner: address,
        keycard_id: u64,
        timestamp: u64,
    }

    #[event]
    /// Emitted when keycard stats are updated
    struct KeycardStatsUpdated has drop, store {
        owner: address,
        tasks_completed: u64,
        avg_score: u64,
        jury_participations: u64,
        variance_flags: u64,
    }

    // ============================================================
    // JUROR REGISTRY EVENTS
    // ============================================================

    #[event]
    /// Emitted when a juror registers for a category
    struct JurorRegistered has drop, store {
        juror: address,
        category: String,
        timestamp: u64,
    }

    #[event]
    /// Emitted when a juror unregisters from a category
    struct JurorUnregistered has drop, store {
        juror: address,
        category: String,
        timestamp: u64,
    }

    // ============================================================
    // ROOM EVENTS
    // ============================================================

    #[event]
    /// Emitted when a new room is created
    struct RoomCreated has drop, store {
        room_id: u64,
        client: address,
        category: String,
        task_reward: u64,
        timestamp: u64,
    }

    #[event]
    /// Emitted when room state transitions
    struct RoomStateChanged has drop, store {
        room_id: u64,
        from_state: u8,
        to_state: u8,
        timestamp: u64,
    }

    #[event]
    /// Emitted when room is settled
    struct RoomSettled has drop, store {
        room_id: u64,
        winner: address,
        final_score: u64,
        payout_amount: u64,
        timestamp: u64,
    }

    #[event]
    /// Emitted when zero valid votes triggers refund
    struct RoomZeroVotesRefunded has drop, store {
        room_id: u64,
        client: address,
        refund_amount: u64,
        timestamp: u64,
    }

    // ============================================================
    // VAULT EVENTS
    // ============================================================

    #[event]
    /// Emitted when escrow is deposited
    struct EscrowDeposited has drop, store {
        room_id: u64,
        depositor: address,
        amount: u64,
        timestamp: u64,
    }

    #[event]
    /// Emitted when escrow is released
    struct EscrowReleased has drop, store {
        room_id: u64,
        recipient: address,
        amount: u64,
        timestamp: u64,
    }

    // ============================================================
    // SUBMISSION EVENTS
    // ============================================================

    #[event]
    /// Emitted when work is submitted
    struct SubmissionCreated has drop, store {
        room_id: u64,
        contributor: address,
        submission_hash: vector<u8>,
        timestamp: u64,
    }

    // ============================================================
    // JURY EVENTS
    // ============================================================

    #[event]
    /// Emitted when jury is assigned to a room
    struct JuryAssigned has drop, store {
        room_id: u64,
        jurors: vector<address>,
        timestamp: u64,
    }

    #[event]
    /// Emitted when a juror commits a vote
    struct VoteCommitted has drop, store {
        room_id: u64,
        juror: address,
        commit_hash: vector<u8>,
        timestamp: u64,
    }

    #[event]
    /// Emitted when a juror reveals their vote
    struct VoteRevealed has drop, store {
        room_id: u64,
        juror: address,
        score: u64,
        timestamp: u64,
    }

    // ============================================================
    // VARIANCE EVENTS
    // ============================================================

    #[event]
    /// Emitted when a juror is flagged for variance
    struct VarianceFlagged has drop, store {
        room_id: u64,
        juror: address,
        score: u64,
        min_distance: u64,
        timestamp: u64,
    }

    // ============================================================
    // SETTLEMENT EVENTS
    // ============================================================

    #[event]
    /// Emitted when client approves settlement
    struct SettlementApproved has drop, store {
        room_id: u64,
        client: address,
        timestamp: u64,
    }

    #[event]
    /// Emitted when final scores are computed
    struct ScoresFinalized has drop, store {
        room_id: u64,
        jury_score: u64,
        timestamp: u64,
    }

    // ============================================================
    // EVENT EMISSION HELPERS
    // ============================================================

    // TODO: Implement emit_keycard_minted(owner, keycard_id, timestamp)
    // TODO: Implement emit_room_created(room_id, client, category, task_reward, timestamp)
    // TODO: Implement emit_room_state_changed(room_id, from_state, to_state, timestamp)
    // TODO: Implement emit_submission_created(room_id, contributor, hash, timestamp)
    // TODO: Implement emit_jury_assigned(room_id, jurors, timestamp)
    // TODO: Implement emit_vote_committed(room_id, juror, hash, timestamp)
    // TODO: Implement emit_vote_revealed(room_id, juror, score, timestamp)
    // TODO: Implement emit_variance_flagged(room_id, juror, score, distance, timestamp)
    // TODO: Implement emit_settlement_approved(room_id, client, timestamp)
    // TODO: Implement emit_room_settled(room_id, winner, score, payout, timestamp)
}
