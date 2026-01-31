# AptosRoom Protocol — Overview

**The Trustless, Proof-of-Skill Talent Layer for Web3**

---

## 🎯 What is AptosRoom?

AptosRoom is a **decentralized talent coordination protocol** built on the Aptos blockchain. It creates trustless task rooms where:

- **Clients** post work and lock payment in escrow
- **Contributors** submit work to earn rewards
- **Jurors** evaluate work quality through cryptographic voting
- **Smart contracts** guarantee fair payment based on dual-key consensus

**Think of it as:** Upwork/Fiverr, but fully decentralized — no platform fees, no disputes, no intermediaries.

---

## ❓ Why Does This Exist?

### The Problem with Freelance Platforms Today

| Problem | Impact |
|---------|--------|
| **Platform fees** | 20-30% taken by intermediaries (Upwork, Fiverr) |
| **Subjective disputes** | Centralized arbitration = unfair outcomes |
| **Fake reviews** | Reputation is gameable and non-portable |
| **Payment delays** | Escrow controlled by platform, not code |
| **No skill verification** | Anyone can claim expertise |

### AptosRoom's Solution

| Solution | How It Works |
|----------|--------------|
| **Zero platform fees** | Smart contracts, not companies |
| **Dual-Key Consensus** | 60% Client + 40% Jury = objective scoring |
| **Soulbound Keycards** | Non-transferable reputation that can't be faked |
| **Trustless Escrow** | Funds locked until settlement, released by code |
| **Proof-of-Skill** | Only those with track records can be jurors |

---

## 👥 Who Is It For?

### Primary Users

| Role | Description | Benefit |
|------|-------------|---------|
| **Clients** | Companies/individuals posting tasks | Guaranteed quality, no platform fees |
| **Contributors** | Freelancers/developers completing work | Fair evaluation, portable reputation |
| **Jurors** | Experienced contributors who evaluate | Earn rewards for honest evaluation |

### Target Markets

1. **Web3 Development** — Smart contract audits, frontend builds
2. **Design & Creative** — Logo design, UI/UX, graphics
3. **Content & Writing** — Technical docs, whitepapers, marketing
4. **DAOs & Grants** — Objective milestone evaluation
5. **Bounty Programs** — Bug bounties with fair payout

---

## 🔧 How It Works

### The Room Lifecycle (7-State Machine)

```
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│   ┌──────┐    ┌──────┐    ┌────────┐    ┌─────────┐    ┌─────────┐ │
│   │ INIT │───▶│ OPEN │───▶│ CLOSED │───▶│  JURY   │───▶│ REVEAL  │ │
│   └──────┘    └──────┘    └────────┘    │ ACTIVE  │    │         │ │
│      │                                   └─────────┘    └────┬────┘ │
│      │                                                       │      │
│      ▼                                                       ▼      │
│  [Escrow                                              ┌───────────┐ │
│   Locked]                                             │ FINALIZED │ │
│                                                       └─────┬─────┘ │
│                                                             │       │
│                                                             ▼       │
│                                                       ┌───────────┐ │
│                                                       │  SETTLED  │ │
│                                                       │  (Final)  │ │
│                                                       └───────────┘ │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### The Flow

1. **Client creates room** → Escrow locked, task posted
2. **Contributors submit work** → One submission per person
3. **Jury selected** → Random selection from qualified pool
4. **Jurors vote (Commit-Reveal)** → Secret voting, then reveal
5. **Variance detection** → Outlier votes flagged, bad actors penalized
6. **Dual-Key Scoring** → 60% Client score + 40% Jury median
7. **Settlement** → Winner receives funds automatically

---

## 🏆 Key Innovations

### 1. Soulbound Keycards (Proof-of-Skill Identity)

- Non-transferable identity tokens
- Track: tasks completed, average score, jury participations, variance flags
- Required to participate as client, contributor, or juror
- **Your reputation travels with you** — not locked in a platform

### 2. Dual-Key Consensus

```
Final Score = (Client Score × 60%) + (Jury Median × 40%)
```

- Client has majority weight (Gold Key)
- Jury provides objective balance (Silver Key)
- Neither can unilaterally decide — **trustless fairness**

### 3. Commit-Reveal Voting

- Jurors commit hash of score + secret salt
- Then reveal actual score
- **Prevents collusion** — you can't copy others' votes

### 4. Nearest-Neighbor Variance Detection

- If your score is >15 points from the nearest other score → **flagged**
- Flagged jurors get reputation penalty
- Protects against manipulation and lazy voting

### 5. Trustless Escrow

- Funds locked at room creation
- Released **only** when:
  - Jury votes are finalized
  - Client approves settlement
- No human override possible — **code is law**

---

## 📊 Current Development Status

### Phase 1: Specification ✅ COMPLETE
- Full protocol specification locked
- CTO-approved, zero ambiguity
- 30+ invariants defined

### Phase 2: Core Implementation 🔄 IN PROGRESS

| Module | Status | Description |
|--------|--------|-------------|
| `keycard.move` | ✅ Complete | Soulbound identity, 5 functions |
| `juror_registry.move` | ✅ Complete | Juror pool management, 3 functions |
| `constants.move` | ✅ Complete | Protocol parameters |
| `events.move` | ✅ Complete | 16 event emission helpers |
| `vault.move` | ✅ Complete | Escrow management, 8 functions |
| `room.move` | ✅ Complete | 7-state machine, 22 functions |
| `jury.move` | 🔄 Scaffold | Random selection, commit-reveal |
| `variance.move` | 🔄 Scaffold | Outlier detection |
| `aggregation.move` | 🔄 Scaffold | Median, scoring |
| `settlement.move` | 🔄 Scaffold | Final payouts |

**Progress:** ~60% of Phase 2 complete

### Upcoming Phases

| Phase | Duration | Status |
|-------|----------|--------|
| Phase 3: Adversarial Hardening | 3 weeks | Pending |
| Phase 4: Keeper Infrastructure | 2 weeks | Pending |
| Phase 5: Backend Indexing | 1 week | Pending |
| Phase 6: Frontend | 2 weeks | Pending |
| Phase 7: Testnet Launch | 3 weeks | Pending |
| Phase 8: Audit & Mainnet | 2 weeks | Pending |

**Target Mainnet:** June 30, 2026

---

## 🛠 Technical Architecture

### Smart Contracts (Move on Aptos)

```
aptosroom-protocol/
├── sources/
│   ├── keycard.move        # Soulbound identity
│   ├── juror_registry.move # Jury pool
│   ├── room.move           # 7-state machine
│   ├── vault.move          # Escrow management
│   ├── jury.move           # Commit-reveal voting
│   ├── variance.move       # Outlier detection
│   ├── aggregation.move    # Score calculation
│   ├── settlement.move     # Payouts
│   ├── constants.move      # Protocol parameters
│   ├── events.move         # Event emission
│   └── errors.move         # Error codes
└── tests/
    └── [comprehensive test suite]
```

### Security Model

| Attack Vector | Defense |
|---------------|---------|
| Sybil (fake accounts) | Keycard required + reputation history |
| Vote manipulation | Commit-reveal + variance detection |
| Collusion | Random jury selection + flagging |
| Client griefing | Dual-key consensus (can't block alone) |
| Escrow theft | Vault locked until settlement |

### Why Aptos?

- **Move language** — resource-oriented, prevents common bugs
- **High throughput** — handles many rooms simultaneously
- **Low fees** — affordable for small tasks
- **Native randomness** — secure jury selection
- **Growing ecosystem** — DeFi, wallets, tooling

---

## 💰 Economic Model

### Fee Structure

| Fee | Amount | Recipient |
|-----|--------|-----------|
| Platform fee | **0%** | None (trustless) |
| Juror rewards | TBD% of task | Jurors |
| Protocol treasury | TBD% | DAO/development |

### Incentive Alignment

| Role | Incentive | Penalty |
|------|-----------|---------|
| Client | Get quality work | Loses escrow if unreasonable |
| Contributor | Earn based on quality | Low scores hurt reputation |
| Juror | Earn for honest votes | Variance flags hurt reputation |

---

## 🔮 Roadmap

### Q1 2026 (Now)
- ✅ Protocol specification complete
- 🔄 Core smart contracts implementation
- 📋 Adversarial testing

### Q2 2026
- Keeper infrastructure
- Backend indexing (GraphQL API)
- Frontend MVP

### Q3 2026
- Testnet launch (Aptos testnet)
- Genesis jury pool (20-30 members)
- Community stress testing

### Q4 2026
- Security audit
- **Mainnet launch**
- First live rooms

---

## 🌟 Why This Matters

### For Web3
- First truly decentralized work marketplace
- Portable reputation across platforms
- DAO-native evaluation system

### For Freelancers
- Keep 100% of earnings
- Fair, objective evaluation
- Reputation you own

### For Clients
- Quality guaranteed by jury consensus
- No platform disputes
- Lower costs, better outcomes

---

## 📞 Contact & Resources

- **GitHub:** https://github.com/virtualconnekt/room-hq
- **Documentation:** [In development]
- **Whitepaper:** Aptos Room WhitePaper V1.pdf

---

## 🤝 The Team

[Your team information here]

---

*"Skill, not wealth. Code, not committees. The future of work is trustless."*

---

**Last Updated:** January 31, 2026  
**Version:** 0.2.0 (Phase 2 In Progress)
