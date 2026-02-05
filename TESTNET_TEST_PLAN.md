# AptosRoom Protocol — Testnet Integration Test Plan

**Version:** 1.1  
**Date:** February 5, 2026  
**Contract:** `0x73b46b42953dbe67a69830d235355e30dc3e10b6f9a1101ce79f63c2b878de5b`  
**Network:** Aptos Testnet

---

## Table of Contents

1. [Test Overview](#test-overview)
2. [Phase 1: Identity & Registration Tests](#phase-1-identity--registration-tests)
3. [Phase 2: Room Lifecycle Tests](#phase-2-room-lifecycle-tests)
4. [Phase 3: Contribution Tests](#phase-3-contribution-tests)
5. [Phase 4: Jury System Tests](#phase-4-jury-system-tests)
6. [Phase 5: Scoring & Variance Tests](#phase-5-scoring--variance-tests)
7. [Phase 6: Settlement Tests](#phase-6-settlement-tests)
8. [Phase 7: Edge Case Tests](#phase-7-edge-case-tests)
9. [Phase 8: Tier System Tests](#phase-8-tier-system-tests)
10. [End-to-End Scenario Tests](#end-to-end-scenario-tests)

---

## Test Overview

### Test Categories

| Phase | Category | # Tests | Priority |
|-------|----------|---------|----------|
| 1 | Identity & Registration | 5 | High |
| 2 | Room Lifecycle | 6 | High |
| 3 | Contributions | 4 | High |
| 4 | Jury System | 8 | Critical |
| 5 | Scoring & Variance | 5 | Critical |
| 6 | Settlement | 6 | Critical |
| 7 | Edge Cases | 6 | Medium |
| 8 | Tier System | 12 | Critical |
| E2E | Full Scenarios | 4 | Critical |

### Test Accounts Needed

| Role | Purpose |
|------|---------|
| **Client** | Creates rooms, deposits escrow, approves settlement |
| **Contributor A** | Submits work to rooms |
| **Contributor B** | Submits work (for competition) |
| **Contributor C** | Submits work (for multi-party tests) |
| **Juror 1-5** | Vote on submissions |
| **Non-Participant** | Tests access control (should be rejected) |

---

## Phase 1: Identity & Registration Tests

### Test 1.1: Create Keycard (First-Time User)

**Purpose:** Verify a new user can create their soulbound identity

**CLI Command:**
```bash
aptos move run \
  --function-id 0x34a1f0...::keycard::mint \
  --assume-yes
```

**Expected Result:**
- Transaction succeeds
- Keycard created with:
  - `tasks_completed: 0`
  - `avg_score: 0`
  - `jury_participations: 0`
  - `variance_flags: 0`

**Frontend Integration:**

```
┌─────────────────────────────────────────────────────────────┐
│                    Welcome to AptosRoom                     │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  🎫 Create Your Keycard                                     │
│                                                             │
│  Your Keycard is your on-chain identity. It tracks:        │
│  • Tasks you complete                                       │
│  • Your average quality score                               │
│  • Jury participations                                      │
│  • Reputation over time                                     │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │             [🔗 Connect Wallet]                      │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │             [✨ Create Keycard]                      │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ⓘ This is a one-time action. Keycards are soulbound.      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**UI Flow:**
1. User connects Petra/Martian wallet
2. Click "Create Keycard" button
3. Wallet prompts for signature
4. Success toast: "Keycard created! Welcome to AptosRoom"
5. Redirect to dashboard

---

### Test 1.2: Prevent Duplicate Keycard

**Purpose:** Verify same address cannot create second keycard

**CLI Command:**
```bash
# Run mint again (should fail)
aptos move run \
  --function-id 0x34a1f0...::keycard::mint \
  --assume-yes
```

**Expected Result:**
- Transaction fails with `E_ALREADY_HAS_KEYCARD`

**Frontend Integration:**
- Button disabled if keycard exists
- Show: "You already have a Keycard" with link to profile

---

### Test 1.3: Query Keycard Stats

**Purpose:** Verify keycard data is queryable

**CLI Command:**
```bash
aptos move view \
  --function-id 0x34a1f0...::keycard::get_tasks_completed \
  --args address:YOUR_ADDRESS

aptos move view \
  --function-id 0x34a1f0...::keycard::get_avg_score \
  --args address:YOUR_ADDRESS

aptos move view \
  --function-id 0x34a1f0...::keycard::get_jury_participations \
  --args address:YOUR_ADDRESS
```

**Expected Result:**
- Returns `0` for new keycard (all stats)

**Frontend Integration:**

```
┌─────────────────────────────────────────────────────────────┐
│                      My Keycard                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │    Tasks    │  │  Avg Score  │  │    Jury     │         │
│  │      0      │  │     --      │  │      0      │         │
│  │  completed  │  │   pending   │  │   sessions  │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
│                                                             │
│  ┌─────────────┐  ┌─────────────┐                          │
│  │  Variance   │  │   Member    │                          │
│  │      0      │  │   Since     │                          │
│  │    flags    │  │  Feb 2026   │                          │
│  └─────────────┘  └─────────────┘                          │
│                                                             │
│  Categories: None registered                                │
│  [+ Add Category]                                           │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

### Test 1.4: Register as Juror

**Purpose:** Verify user can register for jury duty in a category

**CLI Command:**
```bash
aptos move run \
  --function-id 0x34a1f0...::juror_registry::register \
  --args string:"logo-design" \
  --assume-yes
```

**Expected Result:**
- Transaction succeeds
- User added to `logo-design` juror pool

**Frontend Integration:**

```
┌─────────────────────────────────────────────────────────────┐
│                   Register as Juror                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Select categories you're qualified to judge:              │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ ☐ logo-design       │ ☐ smart-contracts             │   │
│  │ ☐ web-development   │ ☐ content-writing             │   │
│  │ ☐ illustration      │ ☐ video-editing               │   │
│  │ ☐ ui-ux-design      │ ☐ data-analysis               │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │               [Register for Selected]                │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ⓘ You'll be randomly selected for jury duty in these      │
│    categories. Earn reputation for fair evaluations.       │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

### Test 1.5: Check Juror Eligibility

**Purpose:** Verify registered juror appears in eligible list

**CLI Command:**
```bash
aptos move view \
  --function-id 0x34a1f0...::juror_registry::is_registered \
  --args address:YOUR_ADDRESS string:"logo-design"
```

**Expected Result:**
- Returns `true`

---

## Phase 2: Room Lifecycle Tests

### Test 2.1: Create Room with Escrow

**Purpose:** Verify client can create a room with APT deposit

**CLI Command:**
```bash
aptos move run \
  --function-id 0x34a1f0...::room::create_room \
  --args \
    string:"Design a modern logo for tech startup" \
    string:"logo-design" \
    u64:100000000 \
    u64:1707696000 \
    u64:1707782400 \
    u64:1707868800 \
  --assume-yes
```

**Parameters:**
- `title`: Task description
- `category`: Skill category
- `task_reward`: 1 APT (100,000,000 octas)
- `deadline_submit`: Unix timestamp for submission deadline
- `deadline_jury_commit`: Unix timestamp for commit deadline
- `deadline_jury_reveal`: Unix timestamp for reveal deadline

**Expected Result:**
- Room created with ID = 1
- State = `STATE_OPEN` (1)
- 1 APT locked in vault

**Frontend Integration:**

```
┌─────────────────────────────────────────────────────────────┐
│                    Create New Room                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Task Title                                                 │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Design a modern logo for tech startup               │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  Description                                                │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Looking for a minimalist, memorable logo that       │   │
│  │ represents innovation and trust. Include:           │   │
│  │ • Primary logo (color + B&W)                        │   │
│  │ • Icon version                                      │   │
│  │ • Source files (AI/SVG)                             │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  Category                    Reward                         │
│  ┌───────────────────┐      ┌───────────────────┐          │
│  │ logo-design    ▼  │      │ 1.0 APT           │          │
│  └───────────────────┘      └───────────────────┘          │
│                                                             │
│  Submission Deadline                                        │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ 📅 February 12, 2026  ⏰ 11:59 PM                   │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │    [Create Room & Deposit 1.0 APT]                   │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ⓘ Your APT will be locked until the task is settled.      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

### Test 2.2: Query Room State

**Purpose:** Verify room state is queryable

**CLI Command:**
```bash
aptos move view \
  --function-id 0x34a1f0...::room::get_state \
  --args u64:1
```

**Expected Result:**
- Returns `1` (STATE_OPEN)

**Frontend Integration:**

```
┌─────────────────────────────────────────────────────────────┐
│  Room #1                                    🟢 OPEN         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  📋 Design a modern logo for tech startup                   │
│                                                             │
│  ┌──────────────┬──────────────┬──────────────┐            │
│  │   Reward     │  Submissions │   Deadline   │            │
│  │   1.0 APT    │      0       │   7 days     │            │
│  └──────────────┴──────────────┴──────────────┘            │
│                                                             │
│  Status: Accepting Submissions                              │
│                                                             │
│  [📤 Submit Your Work]                                      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

### Test 2.3: Query Vault Balance

**Purpose:** Verify escrow is locked

**CLI Command:**
```bash
aptos move view \
  --function-id 0x34a1f0...::vault::get_balance \
  --args u64:1
```

**Expected Result:**
- Returns `100000000` (1 APT)

---

### Test 2.4: Close Room (By Client)

**Purpose:** Verify client can close room for submissions

**CLI Command:**
```bash
aptos move run \
  --function-id 0x34a1f0...::room::close_room \
  --args u64:1 \
  --assume-yes
```

**Expected Result:**
- Room transitions to `STATE_CLOSED` (2)

**Frontend Integration:**

```
┌─────────────────────────────────────────────────────────────┐
│  Room #1                                   🟡 CLOSED        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  📋 Design a modern logo for tech startup                   │
│                                                             │
│  ┌──────────────┬──────────────┬──────────────┐            │
│  │   Reward     │  Submissions │    Status    │            │
│  │   1.0 APT    │      3       │   Closed     │            │
│  └──────────────┴──────────────┴──────────────┘            │
│                                                             │
│  ⏳ Waiting for jury phase to begin...                      │
│                                                             │
│  [👨‍⚖️ Start Jury Phase] (Client only)                       │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

### Test 2.5: Start Jury Phase

**Purpose:** Verify client can initiate jury selection

**CLI Command:**
```bash
aptos move run \
  --function-id 0x34a1f0...::room::start_jury_phase \
  --args u64:1 \
  --assume-yes
```

**Expected Result:**
- Room transitions to `STATE_JURY_ACTIVE` (3)
- 5 jurors randomly selected from registry

---

### Test 2.6: Query Jury Pool

**Purpose:** Verify jury was selected

**CLI Command:**
```bash
aptos move view \
  --function-id 0x34a1f0...::room::get_jury_pool \
  --args u64:1
```

**Expected Result:**
- Returns vector of 5 addresses

**Frontend Integration:**

```
┌─────────────────────────────────────────────────────────────┐
│  Room #1                              🔵 JURY ACTIVE        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  📋 Design a modern logo for tech startup                   │
│                                                             │
│  Selected Jury (5 members):                                 │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ 1. 0x1234...abcd  ⏳ Pending                        │   │
│  │ 2. 0x5678...efgh  ⏳ Pending                        │   │
│  │ 3. 0x9abc...ijkl  ⏳ Pending                        │   │
│  │ 4. 0xdef0...mnop  ⏳ Pending                        │   │
│  │ 5. 0x1357...qrst  ⏳ Pending                        │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  Commit Phase: 0/5 votes submitted                          │
│  ━━━━━━━━━━░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  0%            │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Phase 3: Contribution Tests

### Test 3.1: Submit Contribution

**Purpose:** Verify contributor can submit work to open room

**CLI Command:**
```bash
aptos move run \
  --function-id 0x34a1f0...::room::submit_contribution \
  --args u64:1 \
  --assume-yes
```

**Expected Result:**
- Contributor added to room's contributor list
- Transaction succeeds

**Frontend Integration:**

```
┌─────────────────────────────────────────────────────────────┐
│                   Submit Your Work                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Room #1: Design a modern logo for tech startup             │
│  Reward: 1.0 APT                                            │
│                                                             │
│  Upload Your Submission                                     │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                                                     │   │
│  │     📁 Drag files here or click to browse           │   │
│  │                                                     │   │
│  │     Supported: PNG, JPG, SVG, AI, PDF               │   │
│  │     Max size: 50MB                                  │   │
│  │                                                     │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  Description (optional)                                     │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ My logo concept focuses on...                       │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              [📤 Submit Entry]                       │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ⓘ You can only submit once per room.                      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

### Test 3.2: Prevent Duplicate Submission

**Purpose:** Verify same contributor cannot submit twice

**CLI Command:**
```bash
# Submit again (should fail)
aptos move run \
  --function-id 0x34a1f0...::room::submit_contribution \
  --args u64:1 \
  --assume-yes
```

**Expected Result:**
- Transaction fails with `E_ALREADY_SUBMITTED`

**Frontend Integration:**
- Show "You've already submitted" message
- Display their submission instead of upload form

---

### Test 3.3: Query Contributors

**Purpose:** Verify contributor list is queryable

**CLI Command:**
```bash
aptos move view \
  --function-id 0x34a1f0...::room::get_contributor_list \
  --args u64:1
```

**Expected Result:**
- Returns vector containing contributor addresses

---

### Test 3.4: Reject Submission to Closed Room

**Purpose:** Verify submissions blocked after room closes

**CLI Command:**
```bash
# Try to submit to closed room (should fail)
aptos move run \
  --function-id 0x34a1f0...::room::submit_contribution \
  --args u64:1 \
  --assume-yes
```

**Expected Result:**
- Transaction fails with `E_INVALID_STATE`

---

## Phase 4: Jury System Tests

### Test 4.1: Commit Vote (As Juror)

**Purpose:** Verify juror can submit hidden vote

**Preparation (Off-chain):**
```javascript
// Generate commitment
const score = 85;
const salt = crypto.randomBytes(32);
const scoreBytes = bcs.serialize("u64", score);
const combined = Buffer.concat([scoreBytes, salt]);
const commitHash = sha3_256(combined);

// SAVE score and salt for reveal!
```

**CLI Command:**
```bash
aptos move run \
  --function-id 0x34a1f0...::jury::commit_vote \
  --args u64:1 hex:COMMIT_HASH_HERE \
  --assume-yes
```

**Expected Result:**
- Vote recorded with hash only
- Score remains hidden

**Frontend Integration:**

```
┌─────────────────────────────────────────────────────────────┐
│                    🗳️ Cast Your Vote                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Room #1: Design a modern logo for tech startup             │
│                                                             │
│  Review Submissions:                                        │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ ┌─────┐  Contributor A                              │   │
│  │ │ 🖼️  │  "Modern minimalist approach..."            │   │
│  │ └─────┘  [View Full Submission]                     │   │
│  ├─────────────────────────────────────────────────────┤   │
│  │ ┌─────┐  Contributor B                              │   │
│  │ │ 🖼️  │  "Bold geometric design..."                 │   │
│  │ └─────┘  [View Full Submission]                     │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  Your Score (0-100):                                        │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              [━━━━━━━●━━━━━━━━━]  85                │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              [🔒 Commit Vote]                        │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ⓘ Your vote is encrypted until reveal phase.              │
│    Save your recovery code in case of issues.              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

### Test 4.2: Check Commit Status

**Purpose:** Verify commit was recorded

**CLI Command:**
```bash
aptos move view \
  --function-id 0x34a1f0...::jury::has_committed \
  --args u64:1 address:JUROR_ADDRESS
```

**Expected Result:**
- Returns `true`

---

### Test 4.3: Prevent Non-Juror Commit

**Purpose:** Verify only selected jurors can vote

**CLI Command:**
```bash
# Non-juror tries to commit (should fail)
aptos move run \
  --function-id 0x34a1f0...::jury::commit_vote \
  --args u64:1 hex:SOME_HASH \
  --assume-yes
```

**Expected Result:**
- Transaction fails with `E_NOT_JUROR`

---

### Test 4.4: Reveal Vote (Matching Hash)

**Purpose:** Verify juror can reveal with correct score/salt

**CLI Command:**
```bash
aptos move run \
  --function-id 0x34a1f0...::jury::reveal_vote \
  --args u64:1 u64:85 hex:SALT_USED_IN_COMMIT \
  --assume-yes
```

**Expected Result:**
- Hash verified successfully
- Score recorded
- Keycard `jury_participations` incremented

**Frontend Integration:**

```
┌─────────────────────────────────────────────────────────────┐
│                   🔓 Reveal Your Vote                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Room #1: Design a modern logo for tech startup             │
│                                                             │
│  Status: REVEAL PHASE                                       │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  3/5      │
│                                                             │
│  Your committed vote is ready to reveal.                    │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              [🔓 Reveal Vote]                        │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ⓘ This will verify your vote and make it public.          │
│    Your keycard will be updated with this participation.   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

After reveal:

```
┌─────────────────────────────────────────────────────────────┐
│                   ✅ Vote Revealed                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Your Score: 85                                             │
│  Status: Verified ✓                                         │
│                                                             │
│  Keycard Updated:                                           │
│  • Jury Participations: 0 → 1                               │
│                                                             │
│  Waiting for other jurors to reveal...                      │
│  Reveals: 4/5                                               │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

### Test 4.5: Reject Mismatched Reveal

**Purpose:** Verify wrong score/salt is rejected

**CLI Command:**
```bash
# Try revealing with wrong score (should fail)
aptos move run \
  --function-id 0x34a1f0...::jury::reveal_vote \
  --args u64:1 u64:90 hex:CORRECT_SALT \
  --assume-yes
```

**Expected Result:**
- Transaction fails with `E_HASH_MISMATCH`

---

### Test 4.6: Query Reveal Status

**Purpose:** Verify reveal count is accurate

**CLI Command:**
```bash
aptos move view \
  --function-id 0x34a1f0...::jury::get_reveal_count \
  --args u64:1
```

**Expected Result:**
- Returns number of reveals (e.g., `4`)

---

### Test 4.7: Prevent Double Reveal

**Purpose:** Verify juror can't reveal twice

**CLI Command:**
```bash
# Try to reveal again (should fail)
aptos move run \
  --function-id 0x34a1f0...::jury::reveal_vote \
  --args u64:1 u64:85 hex:SAME_SALT \
  --assume-yes
```

**Expected Result:**
- Transaction fails with `E_ALREADY_REVEALED`

---

### Test 4.8: Query Revealed Scores

**Purpose:** Verify revealed scores are accessible

**CLI Command:**
```bash
aptos move view \
  --function-id 0x34a1f0...::room::get_revealed_scores \
  --args u64:1
```

**Expected Result:**
- Returns vector of revealed scores (e.g., `[85, 82, 88, 80]`)

---

## Phase 5: Scoring & Variance Tests

### Test 5.1: Detect Variance (Outlier)

**Purpose:** Verify outlier detection works

**Scenario:**
- Votes: [85, 82, 88, 80, 15]
- Juror with score 15 should be flagged (>15 points from nearest)

**CLI Command:**
```bash
# This happens during finalize
aptos move view \
  --function-id 0x34a1f0...::variance::is_outlier \
  --args u64:15 u64:4 "vector<u64>:[85,82,88,80,15]"
```

**Expected Result:**
- Returns `true` (15 is an outlier)

**Frontend Integration:**

```
┌─────────────────────────────────────────────────────────────┐
│                   Jury Scores Analysis                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Revealed Votes:                                            │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Juror 1: 85  ✓                                      │   │
│  │ Juror 2: 82  ✓                                      │   │
│  │ Juror 3: 88  ✓                                      │   │
│  │ Juror 4: 80  ✓                                      │   │
│  │ Juror 5: 15  ⚠️ FLAGGED (outlier)                   │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  Valid Scores: [80, 82, 85, 88]                             │
│  Jury Median: 83.5                                          │
│                                                             │
│  1 vote excluded (variance > 15 points)                     │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

### Test 5.2: Calculate Jury Score (Median)

**Purpose:** Verify median calculation

**CLI Command:**
```bash
aptos move run \
  --function-id 0x34a1f0...::room::finalize \
  --args u64:1 \
  --assume-yes
```

**Expected Result:**
- Room transitions to `STATE_FINALIZED` (5)
- Jury score calculated as median of valid votes

---

### Test 5.3: Calculate Final Score (60/40)

**Purpose:** Verify dual-key weighted scoring

**Scenario:**
- Client score: 90
- Jury score (median): 84
- Final = (0.6 × 90) + (0.4 × 84) = 54 + 33.6 = 87.6 → 87

**CLI Command:**
```bash
aptos move view \
  --function-id 0x34a1f0...::room::get_final_score \
  --args u64:1 address:CONTRIBUTOR_ADDRESS
```

**Expected Result:**
- Returns calculated final score

**Frontend Integration:**

```
┌─────────────────────────────────────────────────────────────┐
│                   Final Score Breakdown                     │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Contributor A: 0x1234...abcd                               │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │                                                      │  │
│  │   Client Score (60%)        Jury Score (40%)         │  │
│  │        90                        84                  │  │
│  │        ↓                         ↓                   │  │
│  │       54.0          +          33.6                  │  │
│  │                                                      │  │
│  │                    ═══════                           │  │
│  │                                                      │  │
│  │               Final Score: 87                        │  │
│  │                                                      │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

### Test 5.4: Query Variance Flags

**Purpose:** Verify flagged juror's keycard updated

**CLI Command:**
```bash
aptos move view \
  --function-id 0x34a1f0...::keycard::get_variance_flags \
  --args address:FLAGGED_JUROR_ADDRESS
```

**Expected Result:**
- Returns `1` (incremented from 0)

---

### Test 5.5: All Votes Flagged (Edge Case)

**Purpose:** Verify zero-valid-votes handling

**Scenario:**
- All 5 jurors flagged as outliers
- Should trigger refund to client

**Expected Result:**
- Escrow refunded to client
- Keycards unchanged

---

## Phase 6: Settlement Tests

### Test 6.1: Client Approval (Gold Key)

**Purpose:** Verify client can approve settlement

**CLI Command:**
```bash
aptos move run \
  --function-id 0x34a1f0...::settlement::approve \
  --args u64:1 \
  --assume-yes
```

**Expected Result:**
- `client_approved` flag set to `true`

**Frontend Integration:**

```
┌─────────────────────────────────────────────────────────────┐
│                   Approve Settlement                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Room #1: Design a modern logo for tech startup             │
│                                                             │
│  Final Rankings:                                            │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ 🥇 Contributor B  │  Score: 91  │  ← WINNER         │   │
│  │ 🥈 Contributor A  │  Score: 87  │                    │   │
│  │ 🥉 Contributor C  │  Score: 72  │                    │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  Payout: 1.0 APT → Contributor B                            │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │           [✅ Approve & Release Funds]               │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ⓘ This action is irreversible.                            │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

### Test 6.2: Execute Settlement

**Purpose:** Verify funds are released to winner

**CLI Command:**
```bash
aptos move run \
  --function-id 0x34a1f0...::settlement::execute \
  --args u64:1 \
  --assume-yes
```

**Expected Result:**
- Room transitions to `STATE_SETTLED` (6)
- Winner receives escrow
- All keycards updated

---

### Test 6.3: Verify Winner Received Funds

**Purpose:** Confirm payout was executed

**CLI Command:**
```bash
aptos account balance --account WINNER_ADDRESS
```

**Expected Result:**
- Balance increased by 1 APT

**Frontend Integration:**

```
┌─────────────────────────────────────────────────────────────┐
│                   🎉 Room Settled                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Room #1: Design a modern logo for tech startup             │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                                                     │   │
│  │        🏆 WINNER: Contributor B                     │   │
│  │                                                     │   │
│  │        Final Score: 91                              │   │
│  │        Payout: 1.0 APT ✓                            │   │
│  │                                                     │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  All Participants:                                          │
│  • Contributor A: +1 task, Score 87 recorded                │
│  • Contributor B: +1 task, Score 91 recorded (WINNER)       │
│  • Contributor C: +1 task, Score 72 recorded                │
│                                                             │
│  Transaction: 0xabc123...                                   │
│  [View on Explorer]                                         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

### Test 6.4: Verify Keycards Updated

**Purpose:** Confirm reputation recorded

**CLI Command:**
```bash
aptos move view \
  --function-id 0x34a1f0...::keycard::get_tasks_completed \
  --args address:CONTRIBUTOR_ADDRESS
```

**Expected Result:**
- Returns `1` (was 0)

---

### Test 6.5: Prevent Post-Settlement Writes

**Purpose:** Verify room is immutable after SETTLED

**CLI Command:**
```bash
# Try to submit to settled room (should fail)
aptos move run \
  --function-id 0x34a1f0...::room::submit_contribution \
  --args u64:1 \
  --assume-yes
```

**Expected Result:**
- Transaction fails with `E_INVALID_STATE`

---

### Test 6.6: Query Winner

**Purpose:** Verify winner is recorded

**CLI Command:**
```bash
aptos move view \
  --function-id 0x34a1f0...::room::get_winner \
  --args u64:1
```

**Expected Result:**
- Returns winner's address

---

## Phase 7: Edge Case Tests

### Test 7.1: Tiebreaker (First Submission Wins)

**Purpose:** Verify tie goes to first submitter

**Scenario:**
- Contributor A submits first, score = 85
- Contributor B submits second, score = 85
- Winner should be Contributor A

**Expected Result:**
- Contributor A wins (first submission)

---

### Test 7.2: Single Contributor Room

**Purpose:** Verify room works with only 1 submission

**Expected Result:**
- Single contributor is automatically the winner
- Still requires jury evaluation

---

### Test 7.3: Minimum Jury Size

**Purpose:** Verify insufficient jurors fails gracefully

**Scenario:**
- Only 2 jurors registered for category
- Room requires 5 jurors

**Expected Result:**
- Transaction fails with `E_INSUFFICIENT_JURORS`

**Frontend Integration:**
- Show warning before room creation
- Display available jurors per category

---

### Test 7.4: Deadline Enforcement

**Purpose:** Verify submissions blocked after deadline

**Scenario:**
- Set deadline to past timestamp
- Try to submit

**Expected Result:**
- Transaction fails with `E_DEADLINE_PASSED`

---

### Test 7.5: Non-Client Settlement Attempt

**Purpose:** Verify only client can approve

**CLI Command:**
```bash
# Non-client tries to approve (should fail)
aptos move run \
  --function-id 0x34a1f0...::settlement::approve \
  --args u64:1 \
  --assume-yes
```

**Expected Result:**
- Transaction fails with `E_NOT_CLIENT`

---

### Test 7.6: Double Approval Prevention

**Purpose:** Verify client can't approve twice

**CLI Command:**
```bash
# Approve again (should fail)
aptos move run \
  --function-id 0x34a1f0...::settlement::approve \
  --args u64:1 \
  --assume-yes
```

**Expected Result:**
- Transaction fails with `E_ALREADY_APPROVED`

---

## End-to-End Scenario Tests

### E2E Test 1: Happy Path (Full Flow)

**Scenario:** Complete room lifecycle with 3 contributors and 5 jurors

```
Timeline:
─────────────────────────────────────────────────────────────────

Day 1: Room Creation
├─ Client creates room with 1 APT escrow
├─ State: INIT → OPEN
└─ Vault: 1 APT locked

Day 1-7: Submissions
├─ Contributor A submits (first)
├─ Contributor B submits (second)
├─ Contributor C submits (third)
└─ 3 submissions recorded

Day 7: Close & Jury Selection
├─ Client closes room
├─ State: OPEN → CLOSED
├─ Client starts jury phase
├─ State: CLOSED → JURY_ACTIVE
└─ 5 jurors randomly selected

Day 7-10: Commit Phase
├─ Juror 1 commits: hash(85|salt1)
├─ Juror 2 commits: hash(82|salt2)
├─ Juror 3 commits: hash(88|salt3)
├─ Juror 4 commits: hash(80|salt4)
└─ Juror 5 commits: hash(15|salt5)  ← outlier

Day 10: Reveal Phase
├─ Client starts reveal phase
├─ State: JURY_ACTIVE → JURY_REVEAL
├─ All 5 jurors reveal their votes
└─ Juror 5 flagged (variance > 15)

Day 10: Finalization
├─ Client finalizes room
├─ State: JURY_REVEAL → FINALIZED
├─ Jury score calculated: median([80,82,85,88]) = 83.5 → 83
├─ Client scores: A=90, B=95, C=70
├─ Final scores:
│   A: (0.6×90) + (0.4×83) = 87
│   B: (0.6×95) + (0.4×83) = 90
│   C: (0.6×70) + (0.4×83) = 75
└─ Winner: Contributor B (highest score)

Day 10: Settlement
├─ Client approves settlement
├─ Settlement executed
├─ State: FINALIZED → SETTLED
├─ Contributor B receives 1 APT
└─ All keycards updated

─────────────────────────────────────────────────────────────────
```

**Verification Checklist:**
- [ ] Room created successfully
- [ ] All 3 submissions recorded
- [ ] 5 jurors selected
- [ ] All commits recorded
- [ ] All reveals verified
- [ ] 1 outlier flagged
- [ ] Jury score correct (median)
- [ ] Final scores correct (60/40)
- [ ] Winner determined correctly
- [ ] Escrow released to winner
- [ ] All keycards updated
- [ ] Room immutable after settlement

---

### E2E Test 2: Zero Valid Votes (All Outliers)

**Scenario:** All jury votes are flagged as outliers

```
Jury Votes: [5, 10, 95, 90, 100]

Variance Analysis:
- 5: nearest is 10, distance = 5 ✓
- 10: nearest is 5, distance = 5 ✓
- 95: nearest is 90, distance = 5 ✓
- 90: nearest is 95, distance = 5 ✓
- 100: nearest is 95, distance = 5 ✓

Wait... this wouldn't trigger all outliers. Let's use:

Jury Votes: [5, 30, 55, 80, 100]

Variance Analysis:
- 5: nearest is 30, distance = 25 > 15 ⚠️ FLAGGED
- 30: nearest is 55, distance = 25 > 15 ⚠️ FLAGGED
- 55: nearest is 30/80, distance = 25 > 15 ⚠️ FLAGGED
- 80: nearest is 55, distance = 25 > 15 ⚠️ FLAGGED
- 100: nearest is 80, distance = 20 > 15 ⚠️ FLAGGED

All votes flagged → Zero valid votes
```

**Expected Result:**
- All 5 votes flagged
- Escrow refunded to client (100%)
- No keycards updated
- Room transitions to SETTLED

---

### E2E Test 3: Multiple Rooms Concurrent

**Scenario:** Run 3 rooms simultaneously

**Purpose:** Verify state isolation between rooms

**Verification:**
- [ ] Room 1 state independent of Room 2
- [ ] Juror can participate in multiple rooms
- [ ] Contributor can submit to multiple rooms
- [ ] Keycard updates accumulate correctly

---

## Frontend Integration Summary

### Pages Required

| Page | Purpose | Key Components |
|------|---------|----------------|
| **Landing** | Welcome, connect wallet | Wallet connect, keycard creation |
| **Dashboard** | Overview of user activity | Stats, active rooms, notifications |
| **Keycard Profile** | View reputation | Stats display, category list |
| **Browse Rooms** | Find open rooms | Filter, search, room cards |
| **Room Detail** | View room info | Status, submissions, jury |
| **Create Room** | New task creation | Form, escrow deposit |
| **Submit Work** | Upload submission | File upload, description |
| **Jury Voting** | Cast vote | Submission review, slider, commit |
| **Reveal Vote** | Reveal committed vote | One-click reveal |
| **Settlement** | Approve & execute | Rankings, approve button |

### State Indicators

| State | Color | Icon | Label |
|-------|-------|------|-------|
| INIT | Gray | ⚪ | Initializing |
| OPEN | Green | 🟢 | Open for Submissions |
| CLOSED | Yellow | 🟡 | Submissions Closed |
| JURY_ACTIVE | Blue | 🔵 | Jury Voting |
| JURY_REVEAL | Purple | 🟣 | Reveal Phase |
| FINALIZED | Orange | 🟠 | Pending Approval |
| SETTLED | Gray | ⚫ | Settled |

---

## Test Execution Checklist

### Phase 1: Identity
- [ ] Test 1.1: Create keycard
- [ ] Test 1.2: Prevent duplicate
- [ ] Test 1.3: Query stats
- [ ] Test 1.4: Register juror
- [ ] Test 1.5: Check eligibility

### Phase 2: Room Lifecycle
- [ ] Test 2.1: Create room
- [ ] Test 2.2: Query state
- [ ] Test 2.3: Query vault
- [ ] Test 2.4: Close room
- [ ] Test 2.5: Start jury
- [ ] Test 2.6: Query jury pool

### Phase 3: Contributions
- [ ] Test 3.1: Submit work
- [ ] Test 3.2: Prevent duplicate
- [ ] Test 3.3: Query contributors
- [ ] Test 3.4: Reject to closed

### Phase 4: Jury System
- [ ] Test 4.1: Commit vote
- [ ] Test 4.2: Check commit
- [ ] Test 4.3: Non-juror blocked
- [ ] Test 4.4: Reveal vote
- [ ] Test 4.5: Mismatch rejected
- [ ] Test 4.6: Reveal count
- [ ] Test 4.7: No double reveal
- [ ] Test 4.8: Query scores

### Phase 5: Scoring
- [ ] Test 5.1: Detect variance
- [ ] Test 5.2: Calculate median
- [ ] Test 5.3: Calculate final
- [ ] Test 5.4: Query flags
- [ ] Test 5.5: Zero valid votes

### Phase 6: Settlement
- [ ] Test 6.1: Client approval
- [ ] Test 6.2: Execute settlement
- [ ] Test 6.3: Verify payout
- [ ] Test 6.4: Keycards updated
- [ ] Test 6.5: No post-settlement writes
- [ ] Test 6.6: Query winner

### Phase 7: Edge Cases
- [ ] Test 7.1: Tiebreaker
- [ ] Test 7.2: Single contributor
- [ ] Test 7.3: Minimum jury
- [ ] Test 7.4: Deadline
- [ ] Test 7.5: Non-client approve
- [ ] Test 7.6: Double approval

### E2E Tests
- [ ] E2E 1: Happy path
- [ ] E2E 2: Zero valid votes
- [ ] E2E 3: Concurrent rooms
- [ ] E2E 4: Full tier-based flow

### Phase 8: Tier System
- [ ] Test 8.1: Tier slot allocation (< 10 contributors)
- [ ] Test 8.2: Tier slot allocation (10-20 contributors)
- [ ] Test 8.3: Tier slot allocation (> 20 contributors)
- [ ] Test 8.4: Commit tier vote
- [ ] Test 8.5: Reveal tier vote
- [ ] Test 8.6: Wrong tier A count rejected
- [ ] Test 8.7: Wrong tier B count rejected
- [ ] Test 8.8: Duplicate in A and B rejected
- [ ] Test 8.9: Non-contributor selection rejected
- [ ] Test 8.10: Tier aggregation majority vote
- [ ] Test 8.11: Tier variance (2-tier gap flagged)
- [ ] Test 8.12: Tier final score calculation

---

## Phase 8: Tier System Tests

### Test 8.1: Tier Slot Allocation (< 10 Contributors)

**Purpose:** Verify correct slot counts for small rooms

**CLI Command:**
```bash
aptos move view \
  --function-id 0x34a1f0...::constants::get_tier_a_slots \
  --args u64:5

aptos move view \
  --function-id 0x34a1f0...::constants::get_tier_b_slots \
  --args u64:5
```

**Expected Result:**
- Tier A slots: 1
- Tier B slots: 2

---

### Test 8.2: Tier Slot Allocation (10-20 Contributors)

**Purpose:** Verify correct slot counts for medium rooms

**CLI Command:**
```bash
aptos move view \
  --function-id 0x34a1f0...::constants::get_tier_a_slots \
  --args u64:15

aptos move view \
  --function-id 0x34a1f0...::constants::get_tier_b_slots \
  --args u64:15
```

**Expected Result:**
- Tier A slots: 3
- Tier B slots: 4

---

### Test 8.3: Tier Slot Allocation (> 20 Contributors)

**Purpose:** Verify correct slot counts for large rooms

**CLI Command:**
```bash
aptos move view \
  --function-id 0x34a1f0...::constants::get_tier_a_slots \
  --args u64:25

aptos move view \
  --function-id 0x34a1f0...::constants::get_tier_b_slots \
  --args u64:25
```

**Expected Result:**
- Tier A slots: 5
- Tier B slots: 7

---

### Test 8.4: Commit Tier Vote

**Purpose:** Verify juror can commit tier selections

**Prerequisites:**
1. Room in JURY_ACTIVE state
2. Juror selected for room
3. At least 3 contributors (for slot testing)

**Compute Hash Off-Chain:**
```python
import hashlib
from typing import List

def compute_tier_commit_hash(
    tier_a: List[str],  # Addresses for Tier A
    tier_b: List[str],  # Addresses for Tier B
    salt: bytes
) -> str:
    # BCS serialize addresses (simplified)
    data = b''
    for addr in tier_a:
        data += bytes.fromhex(addr[2:])  # Remove 0x prefix
    for addr in tier_b:
        data += bytes.fromhex(addr[2:])
    data += salt
    return '0x' + hashlib.sha3_256(data).hexdigest()
```

**CLI Command:**
```bash
aptos move run \
  --function-id 0x34a1f0...::jury::commit_tier_vote \
  --args u64:ROOM_ID "hex:COMMIT_HASH" \
  --assume-yes
```

**Expected Result:**
- Transaction succeeds
- TierVoteCommitted event emitted
- `has_committed_tier_vote(room_id, juror)` returns true

---

### Test 8.5: Reveal Tier Vote

**Purpose:** Verify juror can reveal tier selections

**Prerequisites:**
1. Room in JURY_REVEAL state
2. Juror has committed tier vote

**CLI Command:**
```bash
aptos move run \
  --function-id 0x34a1f0...::jury::reveal_tier_vote \
  --args u64:ROOM_ID \
    "vector<address>:TIER_A_ADDRESSES" \
    "vector<address>:TIER_B_ADDRESSES" \
    "hex:SALT" \
  --assume-yes
```

**Expected Result:**
- Transaction succeeds
- TierVoteRevealed event emitted
- `has_revealed_tier_vote(room_id, juror)` returns true
- Keycard jury_participations incremented

---

### Test 8.6: Wrong Tier A Count Rejected

**Purpose:** Verify exact slot count enforcement

**CLI Command:**
```bash
# With 5 contributors, Tier A must be exactly 1
# Try with 2 addresses - should fail
aptos move run \
  --function-id 0x34a1f0...::jury::reveal_tier_vote \
  --args u64:ROOM_ID \
    "vector<address>:addr1,addr2" \
    "vector<address>:addr3,addr4" \
    "hex:SALT" \
  --assume-yes
```

**Expected Result:**
- Transaction fails with `E_INVALID_TIER_A_COUNT` (611)

---

### Test 8.7: Wrong Tier B Count Rejected

**Purpose:** Verify exact slot count enforcement

**CLI Command:**
```bash
# With 5 contributors, Tier B must be exactly 2
# Try with 1 address - should fail
aptos move run \
  --function-id 0x34a1f0...::jury::reveal_tier_vote \
  --args u64:ROOM_ID \
    "vector<address>:addr1" \
    "vector<address>:addr2" \
    "hex:SALT" \
  --assume-yes
```

**Expected Result:**
- Transaction fails with `E_INVALID_TIER_B_COUNT` (612)

---

### Test 8.8: Duplicate in A and B Rejected

**Purpose:** Verify same address cannot be in both tiers

**CLI Command:**
```bash
# Same address in both Tier A and Tier B
aptos move run \
  --function-id 0x34a1f0...::jury::reveal_tier_vote \
  --args u64:ROOM_ID \
    "vector<address>:addr1" \
    "vector<address>:addr1,addr2" \
    "hex:SALT" \
  --assume-yes
```

**Expected Result:**
- Transaction fails with `E_DUPLICATE_IN_TIERS` (613)

---

### Test 8.9: Non-Contributor Selection Rejected

**Purpose:** Verify only actual contributors can be selected

**CLI Command:**
```bash
# Address that didn't contribute to this room
aptos move run \
  --function-id 0x34a1f0...::jury::reveal_tier_vote \
  --args u64:ROOM_ID \
    "vector<address>:NON_CONTRIBUTOR_ADDR" \
    "vector<address>:addr2,addr3" \
    "hex:SALT" \
  --assume-yes
```

**Expected Result:**
- Transaction fails with `E_NOT_A_CONTRIBUTOR` (614)

---

### Test 8.10: Tier Aggregation Majority Vote

**Purpose:** Verify majority voting determines final tier

**Scenario:**
- 5 jurors vote on contributor X
- Juror 1: Tier A
- Juror 2: Tier A  
- Juror 3: Tier A
- Juror 4: Tier B
- Juror 5: Tier C

**CLI Command (after aggregation):**
```bash
aptos move view \
  --function-id 0x34a1f0...::aggregation::get_contributor_tier \
  --args u64:ROOM_ID address:CONTRIBUTOR_X

aptos move view \
  --function-id 0x34a1f0...::aggregation::get_contributor_jury_score \
  --args u64:ROOM_ID address:CONTRIBUTOR_X
```

**Expected Result:**
- Tier: 1 (Tier A - majority)
- Jury Score: 40

---

### Test 8.11: Tier Variance (2-Tier Gap Flagged)

**Purpose:** Verify jurors 2+ tiers from majority are flagged

**Scenario:**
- Majority votes Tier A for contributor X
- One juror votes Tier C (2 tiers away)

**Expected Result:**
- Juror who voted Tier C is flagged
- Keycard variance_flags incremented for flagged juror
- TierVarianceFlagged event emitted

---

### Test 8.12: Tier Final Score Calculation

**Purpose:** Verify final score formula with tier system

**Formula:** `Final = (Client × 60 / 100) + Tier Score`

**Test Cases:**

| Client Score | Tier | Tier Score | Expected Final |
|--------------|------|------------|----------------|
| 100 | A | 40 | 100 |
| 100 | B | 30 | 90 |
| 100 | C | 20 | 80 |
| 90 | A | 40 | 94 |
| 90 | B | 30 | 84 |
| 90 | C | 20 | 74 |
| 80 | A | 40 | 88 |
| 50 | C | 20 | 50 |

**CLI Command:**
```bash
aptos move view \
  --function-id 0x34a1f0...::aggregation::get_final_score \
  --args u64:ROOM_ID address:CONTRIBUTOR
```

---

## E2E Test 4: Full Tier-Based Flow

**Purpose:** Complete end-to-end test using tier system

### Scenario Setup

| Account | Role |
|---------|------|
| Client | Creates room with 1000 APT escrow |
| Contributor A | Best work - should get Tier A |
| Contributor B | Good work - should get Tier B |
| Contributor C | Average work - should get Tier C |
| Jurors 1-5 | All vote consistently |

### Flow

1. **Client creates room** with 3 contributors expected
2. **3 contributors submit work**
3. **Room transitions to JURY_ACTIVE**
4. **5 jurors commit tier votes:**
   - All select Contributor A for Tier A
   - All select Contributor B for Tier B
   - Contributor C defaults to Tier C
5. **Room transitions to JURY_REVEAL**
6. **5 jurors reveal tier votes**
7. **Aggregate tier votes** → compute per-contributor tiers
8. **Client sets scores:** A=95, B=85, C=75
9. **Process final scores:**
   - A: (95 × 0.6) + 40 = 97
   - B: (85 × 0.6) + 30 = 81
   - C: (75 × 0.6) + 20 = 65
10. **Client approves settlement**
11. **Execute tier settlement**
12. **Contributor A wins** (highest score 97)

### Verification

```bash
# Verify winner
aptos move view \
  --function-id 0x34a1f0...::settlement::get_winner \
  --args u64:ROOM_ID
# Expected: Contributor A address

# Verify final scores
aptos move view \
  --function-id 0x34a1f0...::aggregation::get_final_score \
  --args u64:ROOM_ID address:CONTRIBUTOR_A
# Expected: 97
```

---

**Document Version:** 1.1  
**Last Updated:** February 4, 2026  
**Contract:** `0x34a1f012718433e11b3515330d2d65093a13ffccc6b31883f490d653382eedcc`  
**Tier System:** Implemented (Phase 8 tests added)
