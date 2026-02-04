# Slot-Limited Tier System — Implementation Plan

**Version:** 1.0  
**Date:** February 4, 2026  
**Status:** Pending Implementation

---

## Table of Contents

1. [Overview](#overview)
2. [Design Specification](#design-specification)
3. [Module Changes](#module-changes)
4. [Implementation Steps](#implementation-steps)
5. [Data Structure Changes](#data-structure-changes)
6. [Function Signatures](#function-signatures)
7. [Test Plan](#test-plan)
8. [Migration Notes](#migration-notes)

---

## Overview

### Current System
- Single jury score (0-100) per room
- Applied uniformly to all contributors
- Complex variance detection with nearest-neighbor

### New System
- Per-contributor tier assignment (A, B, C)
- Slot-limited tiers (A and B)
- Default tier C for all contributors
- Jurors promote contributors to A or B
- Simple majority-based consensus

---

## Design Specification

### Tier Slot Allocation

| Contributors | Tier A Slots | Tier B Slots | Tier C |
|--------------|--------------|--------------|--------|
| < 10         | 1            | 2            | Rest   |
| 10-20        | 3            | 4            | Rest   |
| > 20         | 5            | 7            | Rest   |

### Tier Scores

| Tier | Jury Score | Meaning |
|------|------------|---------|
| A    | 40         | Excellent - Top performers |
| B    | 30         | Good - Above average |
| C    | 20         | General - Default/Below average |

### Final Score Formula

```
Final Score = (0.6 × Client Score) + Jury Tier Score
```

**Examples:**
- Client=95, Tier A: (0.6 × 95) + 40 = 97
- Client=80, Tier B: (0.6 × 80) + 30 = 78
- Client=70, Tier C: (0.6 × 70) + 20 = 62

---

## Module Changes

### 1. `constants.move` — Add Tier Constants

**Changes:** Add new constants for tier scores and slot allocation

```move
// NEW CONSTANTS TO ADD

/// Tier jury scores
public fun TIER_A_SCORE(): u64 { 40 }
public fun TIER_B_SCORE(): u64 { 30 }
public fun TIER_C_SCORE(): u64 { 20 }

/// Tier identifiers
public fun TIER_A(): u8 { 1 }
public fun TIER_B(): u8 { 2 }
public fun TIER_C(): u8 { 3 }

/// Slot thresholds
public fun SLOT_THRESHOLD_LOW(): u64 { 10 }
public fun SLOT_THRESHOLD_HIGH(): u64 { 20 }

/// Tier A slots by contributor count
public fun TIER_A_SLOTS_LOW(): u64 { 1 }   // < 10 contributors
public fun TIER_A_SLOTS_MID(): u64 { 3 }   // 10-20 contributors
public fun TIER_A_SLOTS_HIGH(): u64 { 5 }  // > 20 contributors

/// Tier B slots by contributor count
public fun TIER_B_SLOTS_LOW(): u64 { 2 }   // < 10 contributors
public fun TIER_B_SLOTS_MID(): u64 { 4 }   // 10-20 contributors
public fun TIER_B_SLOTS_HIGH(): u64 { 7 }  // > 20 contributors
```

**Effort:** 30 minutes

---

### 2. `room.move` — Update Vote Structure

**Changes:** Replace single-score Vote with tier-based Vote

#### Current Structure (Remove)
```move
struct Vote has store {
    juror: address,
    score_commit: vector<u8>,
    revealed: bool,
    revealed_score: Option<u64>,
    revealed_salt: Option<vector<u8>>,
    committed_at: u64,
    variance_flagged: bool,
}
```

#### New Structure (Add)
```move
struct TierVote has store {
    juror: address,
    /// Committed hash of tier assignments
    /// Hash = SHA3(tier_a_addresses || tier_b_addresses || salt)
    commit_hash: vector<u8>,
    /// Addresses promoted to Tier A (revealed)
    tier_a_selections: vector<address>,
    /// Addresses promoted to Tier B (revealed)
    tier_b_selections: vector<address>,
    /// Salt used for commit
    salt: vector<u8>,
    /// Timestamps
    committed_at: u64,
    revealed_at: u64,
    /// Status flags
    committed: bool,
    revealed: bool,
}
```

#### Room Struct Changes
```move
struct Room has key, store {
    // ... existing fields ...
    
    // REMOVE:
    // votes: Table<address, Vote>,
    // jury_score: u64,
    // jury_score_computed: bool,
    
    // ADD:
    tier_votes: Table<address, TierVote>,
    /// Per-contributor jury tier (after aggregation)
    contributor_tiers: Table<address, u8>,
    /// Per-contributor jury score (derived from tier)
    jury_scores: Table<address, u64>,
    /// Whether tiers have been computed
    tiers_computed: bool,
}
```

#### New Helper Functions
```move
/// Calculate tier slots based on contributor count
public fun get_tier_slots(contributor_count: u64): (u64, u64) {
    if (contributor_count < constants::SLOT_THRESHOLD_LOW()) {
        (constants::TIER_A_SLOTS_LOW(), constants::TIER_B_SLOTS_LOW())
    } else if (contributor_count <= constants::SLOT_THRESHOLD_HIGH()) {
        (constants::TIER_A_SLOTS_MID(), constants::TIER_B_SLOTS_MID())
    } else {
        (constants::TIER_A_SLOTS_HIGH(), constants::TIER_B_SLOTS_HIGH())
    }
}

/// Get jury score for a tier
public fun tier_to_score(tier: u8): u64 {
    if (tier == constants::TIER_A()) { constants::TIER_A_SCORE() }
    else if (tier == constants::TIER_B()) { constants::TIER_B_SCORE() }
    else { constants::TIER_C_SCORE() }
}
```

**Effort:** 1.5 hours

---

### 3. `jury.move` — Rewrite Commit/Reveal

**Changes:** Complete rewrite of voting functions

#### Remove
- `commit_vote(account, room_id, score_commit)`
- `reveal_vote(account, room_id, score, salt)`
- `compute_commit_hash(score, salt)`

#### Add
```move
/// Commit tier selections
/// tier_a_selections: Addresses to promote to Tier A
/// tier_b_selections: Addresses to promote to Tier B
/// All other contributors remain in Tier C
public entry fun commit_tier_vote(
    account: &signer,
    room_id: u64,
    commit_hash: vector<u8>,
) {
    let juror = signer::address_of(account);
    
    // Verify room state
    assert!(room::get_state(room_id) == constants::STATE_JURY_ACTIVE(), 
            errors::E_NOT_IN_COMMIT_PHASE());
    
    // Verify juror is selected
    assert!(room::is_juror(room_id, juror), errors::E_NOT_JUROR());
    
    // Verify not already committed
    assert!(!room::has_committed_tier_vote(room_id, juror), 
            errors::E_ALREADY_COMMITTED());
    
    // Store commit
    room::add_tier_vote_commit(room_id, juror, commit_hash);
    
    // Emit event
    event::emit(TierVoteCommitted {
        room_id,
        juror,
        commit_hash,
        timestamp: timestamp::now_seconds(),
    });
}

/// Reveal tier selections
public entry fun reveal_tier_vote(
    account: &signer,
    room_id: u64,
    tier_a_selections: vector<address>,
    tier_b_selections: vector<address>,
    salt: vector<u8>,
) {
    let juror = signer::address_of(account);
    
    // Verify room state
    assert!(room::get_state(room_id) == constants::STATE_JURY_REVEAL(), 
            errors::E_NOT_IN_REVEAL_PHASE());
    
    // Verify juror has committed
    assert!(room::has_committed_tier_vote(room_id, juror), 
            errors::E_NOT_COMMITTED());
    
    // Verify not already revealed
    assert!(!room::has_revealed_tier_vote(room_id, juror), 
            errors::E_ALREADY_REVEALED());
    
    // Verify slot limits
    let contributor_count = room::get_contributor_count(room_id);
    let (max_a, max_b) = room::get_tier_slots(contributor_count);
    assert!(vector::length(&tier_a_selections) == max_a, 
            errors::E_INVALID_TIER_A_COUNT());
    assert!(vector::length(&tier_b_selections) == max_b, 
            errors::E_INVALID_TIER_B_COUNT());
    
    // Verify all selections are valid contributors
    verify_selections_are_contributors(room_id, &tier_a_selections);
    verify_selections_are_contributors(room_id, &tier_b_selections);
    
    // Verify no duplicates between A and B
    verify_no_duplicates(&tier_a_selections, &tier_b_selections);
    
    // Verify hash matches commit
    let expected_hash = compute_tier_commit_hash(
        &tier_a_selections, 
        &tier_b_selections, 
        &salt
    );
    let actual_hash = room::get_tier_vote_commit(room_id, juror);
    assert!(expected_hash == actual_hash, errors::E_HASH_MISMATCH());
    
    // Store reveal
    room::mark_tier_vote_revealed(
        room_id, 
        juror, 
        tier_a_selections, 
        tier_b_selections, 
        salt
    );
    
    // Increment jury participation
    keycard::increment_jury_participations(juror);
    
    // Emit event
    event::emit(TierVoteRevealed {
        room_id,
        juror,
        tier_a_count: vector::length(&tier_a_selections),
        tier_b_count: vector::length(&tier_b_selections),
        timestamp: timestamp::now_seconds(),
    });
}

/// Compute hash for tier vote commit
public fun compute_tier_commit_hash(
    tier_a: &vector<address>,
    tier_b: &vector<address>,
    salt: &vector<u8>,
): vector<u8> {
    let data = vector::empty<u8>();
    
    // Serialize tier A addresses
    let a_bytes = bcs::to_bytes(tier_a);
    vector::append(&mut data, a_bytes);
    
    // Serialize tier B addresses
    let b_bytes = bcs::to_bytes(tier_b);
    vector::append(&mut data, b_bytes);
    
    // Append salt
    vector::append(&mut data, *salt);
    
    // Return hash
    hash::sha3_256(data)
}
```

#### New Events
```move
#[event]
struct TierVoteCommitted has drop, store {
    room_id: u64,
    juror: address,
    commit_hash: vector<u8>,
    timestamp: u64,
}

#[event]
struct TierVoteRevealed has drop, store {
    room_id: u64,
    juror: address,
    tier_a_count: u64,
    tier_b_count: u64,
    timestamp: u64,
}
```

**Effort:** 2 hours

---

### 4. `variance.move` — Simplify Outlier Detection

**Changes:** Replace nearest-neighbor with tier-distance check

#### Current Logic (Remove)
```move
// Complex nearest-neighbor variance detection
public fun detect_outliers(scores: vector<u64>): vector<bool>
```

#### New Logic (Add)
```move
/// Detect outlier jurors based on tier distance from majority
/// A juror is flagged if their tier is 2 steps away from majority
public fun detect_tier_outliers(
    room_id: u64,
    contributor: address,
): vector<address> {
    let jury_pool = room::get_jury_pool(room_id);
    let flagged = vector::empty<address>();
    
    // Count tier votes for this contributor
    let a_count = 0u64;
    let b_count = 0u64;
    let c_count = 0u64;
    
    let i = 0;
    let len = vector::length(&jury_pool);
    while (i < len) {
        let juror = *vector::borrow(&jury_pool, i);
        let tier = room::get_juror_tier_for_contributor(room_id, juror, contributor);
        
        if (tier == constants::TIER_A()) { a_count = a_count + 1; }
        else if (tier == constants::TIER_B()) { b_count = b_count + 1; }
        else { c_count = c_count + 1; };
        
        i = i + 1;
    };
    
    // Determine majority tier
    let majority_tier = if (a_count >= b_count && a_count >= c_count) {
        constants::TIER_A()
    } else if (b_count >= c_count) {
        constants::TIER_B()
    } else {
        constants::TIER_C()
    };
    
    // Flag jurors who are 2 tiers away from majority
    let j = 0;
    while (j < len) {
        let juror = *vector::borrow(&jury_pool, j);
        let tier = room::get_juror_tier_for_contributor(room_id, juror, contributor);
        
        // A to C = 2 steps, C to A = 2 steps
        let distance = if (tier > majority_tier) {
            tier - majority_tier
        } else {
            majority_tier - tier
        };
        
        if (distance >= 2) {
            vector::push_back(&mut flagged, juror);
            // Increment variance flag on keycard
            keycard::increment_variance_flags(juror);
        };
        
        j = j + 1;
    };
    
    flagged
}
```

**Effort:** 1 hour

---

### 5. `aggregation.move` — Per-Contributor Tier Aggregation

**Changes:** Replace median with majority vote per contributor

#### Current Logic (Remove)
```move
public fun compute_jury_score(room_id: u64): u64
```

#### New Logic (Add)
```move
/// Compute jury tier for each contributor based on majority vote
public fun compute_contributor_tiers(room_id: u64) {
    let contributors = room::get_contributor_list(room_id);
    let jury_pool = room::get_jury_pool(room_id);
    let jury_size = vector::length(&jury_pool);
    
    let i = 0;
    let len = vector::length(&contributors);
    while (i < len) {
        let contributor = *vector::borrow(&contributors, i);
        
        // Count tier votes for this contributor
        let a_count = 0u64;
        let b_count = 0u64;
        let c_count = 0u64;
        
        let j = 0;
        while (j < jury_size) {
            let juror = *vector::borrow(&jury_pool, j);
            let tier = get_juror_tier_for_contributor(room_id, juror, contributor);
            
            if (tier == constants::TIER_A()) { a_count = a_count + 1; }
            else if (tier == constants::TIER_B()) { b_count = b_count + 1; }
            else { c_count = c_count + 1; };
            
            j = j + 1;
        };
        
        // Determine majority tier
        let final_tier = if (a_count >= b_count && a_count >= c_count) {
            constants::TIER_A()
        } else if (b_count >= c_count) {
            constants::TIER_B()
        } else {
            constants::TIER_C()
        };
        
        // Run variance detection for this contributor
        variance::detect_tier_outliers(room_id, contributor);
        
        // Store final tier and score
        let jury_score = room::tier_to_score(final_tier);
        room::set_contributor_tier(room_id, contributor, final_tier);
        room::set_jury_score(room_id, contributor, jury_score);
        
        i = i + 1;
    };
    
    room::mark_tiers_computed(room_id);
}

/// Helper: Get what tier a juror assigned to a contributor
fun get_juror_tier_for_contributor(
    room_id: u64,
    juror: address,
    contributor: address,
): u8 {
    let tier_a = room::get_juror_tier_a_selections(room_id, juror);
    let tier_b = room::get_juror_tier_b_selections(room_id, juror);
    
    if (vector::contains(&tier_a, &contributor)) {
        constants::TIER_A()
    } else if (vector::contains(&tier_b, &contributor)) {
        constants::TIER_B()
    } else {
        constants::TIER_C()
    }
}
```

**Effort:** 1.5 hours

---

### 6. `settlement.move` — Update Final Score Calculation

**Changes:** Use per-contributor jury scores

#### Current Logic
```move
let jury_score = room::get_jury_score(room_id);
let final = (client_score * 60 / 100) + (jury_score * 40 / 100);
```

#### New Logic
```move
let jury_score = room::get_jury_score_for_contributor(room_id, contributor);
let final = (client_score * 60 / 100) + jury_score;
// Note: jury_score is already the tier value (40, 30, or 20)
```

**Effort:** 30 minutes

---

### 7. `errors.move` — Add New Error Codes

```move
// NEW ERROR CODES

/// Invalid tier A selection count
public fun E_INVALID_TIER_A_COUNT(): u64 { 20 }

/// Invalid tier B selection count
public fun E_INVALID_TIER_B_COUNT(): u64 { 21 }

/// Duplicate contributor in tier selections
public fun E_DUPLICATE_IN_TIERS(): u64 { 22 }

/// Selected address is not a contributor
public fun E_NOT_A_CONTRIBUTOR(): u64 { 23 }

/// Tiers not yet computed
public fun E_TIERS_NOT_COMPUTED(): u64 { 24 }
```

**Effort:** 15 minutes

---

## Implementation Steps

### Phase 1: Constants & Errors (45 min)
1. [ ] Add tier constants to `constants.move`
2. [ ] Add new error codes to `errors.move`
3. [ ] Compile and verify

### Phase 2: Room Structure (2 hrs)
1. [ ] Add `TierVote` struct to `room.move`
2. [ ] Update `Room` struct with new fields
3. [ ] Add helper functions (`get_tier_slots`, `tier_to_score`)
4. [ ] Add friend functions for tier vote storage
5. [ ] Compile and fix any issues

### Phase 3: Jury Voting (2.5 hrs)
1. [ ] Remove old `commit_vote` and `reveal_vote`
2. [ ] Implement `commit_tier_vote`
3. [ ] Implement `reveal_tier_vote`
4. [ ] Implement `compute_tier_commit_hash`
5. [ ] Add validation helpers
6. [ ] Add new events
7. [ ] Compile and test

### Phase 4: Variance Detection (1 hr)
1. [ ] Remove old nearest-neighbor detection
2. [ ] Implement tier-distance outlier detection
3. [ ] Integrate with keycard flagging
4. [ ] Compile and test

### Phase 5: Aggregation (1.5 hrs)
1. [ ] Remove old median calculation
2. [ ] Implement per-contributor tier aggregation
3. [ ] Add majority vote logic
4. [ ] Integrate variance detection
5. [ ] Compile and test

### Phase 6: Settlement (30 min)
1. [ ] Update final score calculation
2. [ ] Use per-contributor jury scores
3. [ ] Compile and test

### Phase 7: Tests (3 hrs)
1. [ ] Update all jury module tests
2. [ ] Update variance module tests
3. [ ] Update aggregation module tests
4. [ ] Update settlement module tests
5. [ ] Add new tier-specific tests
6. [ ] Run full test suite

### Phase 8: Documentation (30 min)
1. [ ] Update whitepaper/spec if needed
2. [ ] Update test plan document
3. [ ] Document API changes

---

## Data Structure Changes

### Before (Current)

```
Room
├── votes: Table<address, Vote>
│   └── Vote
│       ├── score_commit: vector<u8>
│       ├── revealed_score: Option<u64>
│       └── ...
├── jury_score: u64
└── jury_score_computed: bool
```

### After (New)

```
Room
├── tier_votes: Table<address, TierVote>
│   └── TierVote
│       ├── commit_hash: vector<u8>
│       ├── tier_a_selections: vector<address>
│       ├── tier_b_selections: vector<address>
│       └── ...
├── contributor_tiers: Table<address, u8>
├── jury_scores: Table<address, u64>
└── tiers_computed: bool
```

---

## Function Signatures

### Removed Functions

| Module | Function | Reason |
|--------|----------|--------|
| `jury` | `commit_vote(account, room_id, score_commit)` | Replaced |
| `jury` | `reveal_vote(account, room_id, score, salt)` | Replaced |
| `jury` | `compute_commit_hash(score, salt)` | Replaced |
| `variance` | `detect_outliers(scores)` | Replaced |
| `aggregation` | `compute_jury_score(room_id)` | Replaced |

### Added Functions

| Module | Function | Purpose |
|--------|----------|---------|
| `constants` | `TIER_A_SCORE()` | Returns 40 |
| `constants` | `TIER_B_SCORE()` | Returns 30 |
| `constants` | `TIER_C_SCORE()` | Returns 20 |
| `constants` | `get_tier_a_slots(count)` | Returns A slot count |
| `constants` | `get_tier_b_slots(count)` | Returns B slot count |
| `room` | `get_tier_slots(count)` | Returns (A, B) slots |
| `room` | `tier_to_score(tier)` | Converts tier to score |
| `jury` | `commit_tier_vote(...)` | Commit tier selections |
| `jury` | `reveal_tier_vote(...)` | Reveal tier selections |
| `jury` | `compute_tier_commit_hash(...)` | Hash for commit |
| `variance` | `detect_tier_outliers(...)` | Tier-based detection |
| `aggregation` | `compute_contributor_tiers(...)` | Per-contributor tiers |

---

## Test Plan

### New Test Cases

| Test | Description | Expected |
|------|-------------|----------|
| `test_tier_slots_low` | < 10 contributors | A=1, B=2 |
| `test_tier_slots_mid` | 10-20 contributors | A=3, B=4 |
| `test_tier_slots_high` | > 20 contributors | A=5, B=7 |
| `test_commit_tier_vote` | Valid commit | Success |
| `test_reveal_tier_vote` | Matching reveal | Success |
| `test_reveal_wrong_count` | Wrong A/B count | Fail |
| `test_reveal_duplicate` | Same address in A and B | Fail |
| `test_reveal_non_contributor` | Invalid address | Fail |
| `test_tier_majority_a` | 3/5 vote A | Final = A |
| `test_tier_majority_b` | 3/5 vote B | Final = B |
| `test_tier_majority_c` | 3/5 vote C | Final = C |
| `test_variance_two_tiers` | 2 tier distance | Flagged |
| `test_variance_one_tier` | 1 tier distance | Not flagged |
| `test_final_score_tier_a` | Client=90, Tier A | 94 |
| `test_final_score_tier_b` | Client=90, Tier B | 84 |
| `test_final_score_tier_c` | Client=90, Tier C | 74 |

---

## Migration Notes

### Breaking Changes

1. **Vote structure changed** — Cannot migrate existing votes
2. **API changed** — Frontend must update commit/reveal calls
3. **Score interpretation** — Jury score now per-contributor

### Deployment Strategy

Since this is a breaking change:

1. **Option A: New Contract** — Deploy as new package
2. **Option B: Upgrade** — If no active rooms, upgrade in place

### Recommended Approach

Deploy as **new version** (`aptosroom_v2`) if there are active rooms on testnet.

---

## Estimated Total Effort

| Phase | Time |
|-------|------|
| Constants & Errors | 45 min |
| Room Structure | 2 hrs |
| Jury Voting | 2.5 hrs |
| Variance Detection | 1 hr |
| Aggregation | 1.5 hrs |
| Settlement | 30 min |
| Tests | 3 hrs |
| Documentation | 30 min |
| **Total** | **~12 hours** |

---

## Approval Checklist

Before implementation:

- [ ] Design reviewed and approved
- [ ] Slot allocation confirmed (1/2, 3/4, 5/7)
- [ ] Tier scores confirmed (40/30/20)
- [ ] Breaking change acknowledged
- [ ] Ready to proceed

---

**Next Step:** Once approved, I will implement Phase 1 (Constants & Errors) and proceed sequentially through all phases.
