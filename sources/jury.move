/// ============================================================
/// MODULE: Jury
/// SPEC: EXECUTION_TASKS_BY_PHASE.md Section 2.4, 2.5
/// INVARIANTS ENFORCED:
///   - INVARIANT_VOTE_001: Hash integrity (commit-reveal)
///   - INVARIANT_VOTE_002: Unpredictable jury selection
/// PURPOSE: Jury selection, commit, and reveal phases
/// ============================================================
module aptosroom::jury {
    use std::signer;
    use std::string::String;
    use std::option::{Self, Option};
    use std::vector;
    use std::hash;
    use std::bcs;
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use aptos_framework::block;
    use aptos_framework::randomness;
    use aptosroom::errors;
    use aptosroom::constants;

    // ============================================================
    // EVENTS
    // ============================================================

    #[event]
    struct JuryAssigned has drop, store {
        room_id: u64,
        jurors: vector<address>,
        timestamp: u64,
    }

    #[event]
    struct VoteCommitted has drop, store {
        room_id: u64,
        juror: address,
        commit_hash: vector<u8>,
        timestamp: u64,
    }

    #[event]
    struct VoteRevealed has drop, store {
        room_id: u64,
        juror: address,
        score: u64,
        timestamp: u64,
    }

    // ============================================================
    // JURY SELECTION
    // ============================================================

    /// Select jurors for a room (INVARIANT_VOTE_002: unpredictable)
    // TODO: Implement select_jurors(
    //   room_id: u64,
    //   category: &String,
    //   eligible_jurors: vector<address>,
    //   jury_size: u64,
    // ): vector<address>
    //
    // Algorithm:
    // 1. Assert vector::length(&eligible_jurors) >= jury_size (E_INSUFFICIENT_JURORS)
    // 2. Get randomness seed from Aptos randomness module
    // 3. Shuffle eligible_jurors using Fisher-Yates with seed
    // 4. Take first jury_size elements
    // 5. Return selected jurors
    //
    // Steps for Fisher-Yates shuffle:
    // for i in (0..len).rev():
    //     j = random_in_range(0, i+1)
    //     swap(list[i], list[j])

    /// Internal: Fisher-Yates shuffle with seed
    // TODO: Implement shuffle_with_seed(
    //   list: &mut vector<address>,
    //   seed: vector<u8>,
    // )
    // Steps:
    // 1. Let n = vector::length(list)
    // 2. For i from n-1 down to 1:
    //    a. Derive j from hash(seed || i) % (i + 1)
    //    b. Swap list[i] and list[j]

    /// Internal: Generate random index
    // TODO: Implement random_index(seed: &vector<u8>, iteration: u64, max: u64): u64
    // Steps:
    // 1. Compute hash(seed || bcs::to_bytes(&iteration))
    // 2. Take first 8 bytes as u64
    // 3. Return value % max

    // ============================================================
    // COMMIT PHASE
    // ============================================================

    /// Commit a vote (hash only, score is secret)
    // TODO: Implement commit_vote(
    //   account: &signer,
    //   room_id: u64,
    //   score_commit: vector<u8>,  // SHA3(score || salt)
    // )
    //
    // Steps:
    // 1. Get juror address from signer
    // 2. Assert room state == STATE_JURY_ACTIVE (E_NOT_IN_COMMIT_PHASE)
    // 3. Assert juror is in room.jury_pool (E_NOT_JUROR)
    // 4. Assert block_height < deadline_jury_commit (E_COMMIT_DEADLINE_PASSED)
    // 5. Assert juror has not already committed (E_ALREADY_COMMITTED)
    // 6. Create Vote struct:
    //    - juror = sender
    //    - score_commit = score_commit
    //    - revealed = false
    //    - revealed_score = None
    //    - revealed_salt = None
    //    - committed_at = now
    //    - variance_flagged = false
    // 7. Add vote to room.votes
    // 8. Emit VoteCommitted event

    /// Check if all jurors have committed
    // TODO: Implement all_committed(room_id: u64): bool
    // Steps:
    // 1. Get jury pool from room
    // 2. For each juror, check if vote exists in room.votes
    // 3. Return true if all have committed

    // ============================================================
    // REVEAL PHASE
    // ============================================================

    /// Reveal a vote (INVARIANT_VOTE_001: hash verification)
    // TODO: Implement reveal_vote(
    //   account: &signer,
    //   room_id: u64,
    //   score: u64,
    //   salt: vector<u8>,
    // )
    //
    // Steps:
    // 1. Get juror address from signer
    // 2. Assert room state == STATE_JURY_REVEAL (E_NOT_IN_REVEAL_PHASE)
    // 3. Assert juror has committed (E_NOT_COMMITTED)
    // 4. Assert !vote.revealed (E_ALREADY_REVEALED)
    // 5. Assert score <= MAX_SCORE (E_INVALID_SCORE)
    // 6. Compute expected_hash = sha3_256(bcs::to_bytes(&score) || salt)
    // 7. Assert expected_hash == vote.score_commit (E_HASH_MISMATCH)
    // 8. Set vote.revealed = true
    // 9. Set vote.revealed_score = Some(score)
    // 10. Set vote.revealed_salt = Some(salt)
    // 11. Emit VoteRevealed event

    /// Compute hash for commit (helper for off-chain)
    // TODO: Implement compute_commit_hash(score: u64, salt: vector<u8>): vector<u8>
    // Steps:
    // 1. Serialize score using BCS
    // 2. Concatenate with salt
    // 3. Return SHA3-256 hash

    /// Check if all jurors have revealed
    // TODO: Implement all_revealed(room_id: u64): bool
    // Steps:
    // 1. Get jury pool from room
    // 2. For each juror:
    //    - If vote exists and vote.revealed == true, continue
    //    - Else return false
    // 3. Return true

    /// Get revealed scores (for variance detection)
    // TODO: Implement get_revealed_scores(room_id: u64): vector<(address, u64)>
    // Steps:
    // 1. Initialize empty result vector
    // 2. For each juror in jury_pool:
    //    - If vote.revealed == true:
    //      - Push (juror, vote.revealed_score)
    // 3. Return result

    // ============================================================
    // VIEW FUNCTIONS
    // ============================================================

    #[view]
    /// Check if juror has committed
    public fun has_committed(_room_id: u64, _juror: address): bool {
        // TODO: Implement - check if vote exists in room.votes
        false
    }

    #[view]
    /// Check if juror has revealed
    public fun has_revealed(_room_id: u64, _juror: address): bool {
        // TODO: Implement - check vote.revealed
        false
    }

    #[view]
    /// Get commit count
    public fun get_commit_count(_room_id: u64): u64 {
        // TODO: Implement - count votes in room.votes
        0
    }

    #[view]
    /// Get reveal count
    public fun get_reveal_count(_room_id: u64): u64 {
        // TODO: Implement - count revealed votes
        0
    }
}
