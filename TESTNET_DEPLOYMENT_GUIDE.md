# AptosRoom Protocol — Testnet Deployment Guide

**Version:** 1.0  
**Date:** February 3, 2026  
**Network:** Aptos Testnet  
**Status:** Ready for Deployment

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Environment Setup](#2-environment-setup)
3. [Account Creation & Funding](#3-account-creation--funding)
4. [Configuration](#4-configuration)
5. [Compilation](#5-compilation)
6. [Deployment](#6-deployment)
7. [Post-Deployment Verification](#7-post-deployment-verification)
8. [Module Initialization](#8-module-initialization)
9. [Testing on Testnet](#9-testing-on-testnet)
10. [Troubleshooting](#10-troubleshooting)
11. [Contract Addresses Reference](#11-contract-addresses-reference)

---

## 1. Prerequisites

### Required Software

| Tool | Version | Purpose |
|------|---------|---------|
| Aptos CLI | ≥ 2.0.0 | Compile, deploy, interact with contracts |
| Git | Any | Version control |
| curl | Any | API requests |

### Install Aptos CLI

**Linux/macOS:**
```bash
curl -fsSL "https://aptos.dev/scripts/install_cli.py" | python3
```

**Verify Installation:**
```bash
aptos --version
# Expected: aptos 2.x.x
```

### Check CLI is Working
```bash
aptos info
```

---

## 2. Environment Setup

### Project Structure
```
aptosroom-protocol/
├── Move.toml                 # Package manifest
├── sources/                  # Move source files (11 modules)
│   ├── constants.move
│   ├── errors.move
│   ├── keycard.move
│   ├── juror_registry.move
│   ├── vault.move
│   ├── room.move
│   ├── jury.move
│   ├── variance.move
│   ├── aggregation.move
│   └── settlement.move
└── tests/                    # Test files
```

### Navigate to Project
```bash
cd /home/abdoulaahmad/Documents/aptos/aptosroom-protocol
```

---

## 3. Account Creation & Funding

### Step 3.1: Initialize Aptos Account

```bash
aptos init --network testnet
```

**You'll be prompted:**
```
Choose how you want to configure your default account:
> Enter: Generate new key pair
```

**Output will show:**
```
Account Address: 0x<YOUR_ADDRESS>
Private Key: 0x<YOUR_PRIVATE_KEY>
Public Key: 0x<YOUR_PUBLIC_KEY>
```

⚠️ **SAVE THESE VALUES SECURELY!**

### Step 3.2: View Your Account Address
```bash
aptos account lookup-address
```

Or check your config:
```bash
cat ~/.aptos/config.yaml
```

### Step 3.3: Fund Your Account (Testnet Faucet)

**Option A: CLI Faucet**
```bash
aptos account fund-with-faucet --account default --amount 100000000
```
(Funds 1 APT = 100,000,000 octas)

**Option B: Web Faucet**
1. Go to: https://aptos.dev/en/network/faucet
2. Select "Testnet"
3. Enter your account address
4. Request funds

**Option C: curl Request**
```bash
curl -X POST "https://faucet.testnet.aptoslabs.com/mint?amount=100000000&address=YOUR_ADDRESS"
```

### Step 3.4: Verify Balance
```bash
aptos account balance --account default
```

**Expected Output:**
```
{
  "Result": [
    {
      "coin_type": "0x1::aptos_coin::AptosCoin",
      "amount": 100000000
    }
  ]
}
```

---

## 4. Configuration

### Step 4.1: Update Move.toml with Your Address

Open `Move.toml` and replace the placeholder address:

**Before:**
```toml
[addresses]
aptosroom = "0xCAFE"
```

**After:**
```toml
[addresses]
aptosroom = "YOUR_ACCOUNT_ADDRESS"
```

Replace `YOUR_ACCOUNT_ADDRESS` with your actual testnet address (e.g., `0x1234...abcd`).

### Step 4.2: Verify Move.toml

Your `Move.toml` should look like:
```toml
[package]
name = "aptosroom-protocol"
version = "0.1.0"
authors = ["AptosRoom Team"]

[addresses]
aptosroom = "0xYOUR_ACTUAL_ADDRESS_HERE"

[dependencies]
AptosFramework = { git = "https://github.com/aptos-labs/aptos-core.git", subdir = "aptos-move/framework/aptos-framework", rev = "mainnet" }
AptosStdlib = { git = "https://github.com/aptos-labs/aptos-core.git", subdir = "aptos-move/framework/aptos-stdlib", rev = "mainnet" }
```

### Step 4.3: Alternative - Use Named Address

You can also use the `default` profile address:
```toml
[addresses]
aptosroom = "_"
```

Then deploy with:
```bash
aptos move publish --named-addresses aptosroom=default
```

---

## 5. Compilation

### Step 5.1: Compile the Package

```bash
aptos move compile
```

**Expected Output:**
```
Compiling, may take a while...
INCLUDING DEPENDENCY AptosFramework
INCLUDING DEPENDENCY AptosStdlib
INCLUDING DEPENDENCY MoveStdlib
BUILDING aptosroom-protocol
{
  "Result": [
    "aptosroom::constants",
    "aptosroom::errors",
    "aptosroom::keycard",
    "aptosroom::juror_registry",
    "aptosroom::vault",
    "aptosroom::room",
    "aptosroom::jury",
    "aptosroom::variance",
    "aptosroom::aggregation",
    "aptosroom::settlement"
  ]
}
```

### Step 5.2: Run Tests (Optional but Recommended)

```bash
aptos move test
```

**Expected Output:**
```
Running Move unit tests
[ PASS ] aptosroom::constants::test_state_values_unique
[ PASS ] aptosroom::constants::test_weights_sum_to_100
... (110 tests total)
Test result: OK. Total tests: 110; passed: 110; failed: 0
```

---

## 6. Deployment

### Step 6.1: Publish to Testnet

**Basic Publish:**
```bash
aptos move publish --assume-yes
```

**With Named Address (if using `_` placeholder):**
```bash
aptos move publish --named-addresses aptosroom=default --assume-yes
```

**With Explicit Gas Settings:**
```bash
aptos move publish \
  --named-addresses aptosroom=default \
  --max-gas 200000 \
  --gas-unit-price 100 \
  --assume-yes
```

### Step 6.2: Expected Output

```
Compiling, may take a while...
INCLUDING DEPENDENCY AptosFramework
INCLUDING DEPENDENCY AptosStdlib
INCLUDING DEPENDENCY MoveStdlib
BUILDING aptosroom-protocol
package size 45678 bytes

Do you want to submit a transaction for a range of [XXXXX - XXXXX] Octas at a gas unit price of 100 Octas? [yes/no] >
yes

{
  "Result": {
    "transaction_hash": "0xabcd1234...",
    "gas_used": 12345,
    "gas_unit_price": 100,
    "sender": "0xYOUR_ADDRESS",
    "sequence_number": 0,
    "success": true,
    "timestamp_us": 1706918400000000,
    "version": 123456789,
    "vm_status": "Executed successfully"
  }
}
```

### Step 6.3: Record the Transaction Hash

Save the `transaction_hash` from the output. You'll use it to verify deployment.

---

## 7. Post-Deployment Verification

### Step 7.1: Verify on Explorer

1. Go to: https://explorer.aptoslabs.com/?network=testnet
2. Search for your transaction hash
3. Confirm status is "Success"

### Step 7.2: Check Published Modules

```bash
aptos account list --query modules --account default
```

**Expected Output:**
```json
{
  "Result": [
    {
      "bytecode": "0x...",
      "abi": {
        "name": "constants",
        "...": "..."
      }
    },
    {
      "bytecode": "0x...",
      "abi": {
        "name": "errors",
        "...": "..."
      }
    },
    // ... 10 modules total
  ]
}
```

### Step 7.3: Verify Specific Module Exists

```bash
aptos move view --function-id YOUR_ADDRESS::constants::STATE_INIT
```

**Expected Output:**
```json
{
  "Result": [0]
}
```

---

## 8. Module Initialization

Some modules require initialization. The `init_module` functions run automatically on publish, but verify:

### Step 8.1: Verify KeycardCounter Exists

```bash
aptos move view \
  --function-id YOUR_ADDRESS::keycard::keycard_exists \
  --args address:YOUR_ADDRESS
```

### Step 8.2: Verify RoomRegistry Exists

Check by trying to query room count (should be 0):
```bash
aptos move view \
  --function-id YOUR_ADDRESS::room::get_room_count
```

---

## 9. Testing on Testnet

### 9.1: Create a Keycard

```bash
aptos move run \
  --function-id YOUR_ADDRESS::keycard::mint \
  --assume-yes
```

### 9.2: Verify Keycard Created

```bash
aptos move view \
  --function-id YOUR_ADDRESS::keycard::keycard_exists \
  --args address:YOUR_ADDRESS
```

**Expected:** `{ "Result": [true] }`

### 9.3: Register as Juror

```bash
aptos move run \
  --function-id YOUR_ADDRESS::juror_registry::register \
  --args string:"design" \
  --assume-yes
```

### 9.4: Create a Room

```bash
aptos move run \
  --function-id YOUR_ADDRESS::room::create_room \
  --args \
    string:"Logo Design Task" \
    string:"design" \
    u64:100000000 \
    u64:1707523200 \
    u64:1707609600 \
    u64:1707696000 \
  --assume-yes
```

### 9.5: Query Room State

```bash
aptos move view \
  --function-id YOUR_ADDRESS::room::get_state \
  --args u64:1
```

**Expected:** `{ "Result": [1] }` (STATE_OPEN)

---

## 10. Troubleshooting

### Error: "Account not found"
```
Solution: Fund your account with faucet
aptos account fund-with-faucet --account default --amount 100000000
```

### Error: "Module not found"
```
Solution: Ensure Move.toml has correct address
Check: aptosroom = "YOUR_ACTUAL_ADDRESS"
```

### Error: "Insufficient gas"
```
Solution: Increase max-gas
aptos move publish --max-gas 500000 --assume-yes
```

### Error: "Address already has module"
```
Solution: This means deployment succeeded. Modules cannot be re-deployed to same address.
To redeploy: Create new account or use upgradeable pattern.
```

### Error: "LINKER_ERROR" or "Dependency not found"
```
Solution: Clean build and retry
rm -rf build/
aptos move compile
aptos move publish
```

### Error: "Transaction expired"
```
Solution: Network congestion. Retry with higher gas price:
aptos move publish --gas-unit-price 150 --assume-yes
```

---

## 11. Contract Addresses Reference

After deployment, record these for frontend integration:

### Module Addresses

| Module | Address |
|--------|---------|
| aptosroom::constants | `YOUR_ADDRESS::constants` |
| aptosroom::errors | `YOUR_ADDRESS::errors` |
| aptosroom::keycard | `YOUR_ADDRESS::keycard` |
| aptosroom::juror_registry | `YOUR_ADDRESS::juror_registry` |
| aptosroom::vault | `YOUR_ADDRESS::vault` |
| aptosroom::room | `YOUR_ADDRESS::room` |
| aptosroom::jury | `YOUR_ADDRESS::jury` |
| aptosroom::variance | `YOUR_ADDRESS::variance` |
| aptosroom::aggregation | `YOUR_ADDRESS::aggregation` |
| aptosroom::settlement | `YOUR_ADDRESS::settlement` |

### Key Entry Functions

| Function | Purpose |
|----------|---------|
| `keycard::mint()` | Create soulbound identity |
| `juror_registry::register(category)` | Join juror pool |
| `room::create_room(...)` | Create task with escrow |
| `room::submit_contribution(room_id)` | Submit work |
| `room::close_room(room_id)` | End submission phase |
| `room::start_jury_phase(room_id)` | Begin jury selection |
| `jury::commit_vote(room_id, hash)` | Submit hidden vote |
| `jury::reveal_vote(room_id, score, salt)` | Reveal vote |
| `room::finalize(room_id)` | Compute final scores |
| `settlement::approve(room_id)` | Client approval |
| `settlement::execute(room_id)` | Release funds |

### Key View Functions

| Function | Returns |
|----------|---------|
| `room::get_state(room_id)` | Current state (0-6) |
| `room::get_jury_pool(room_id)` | Selected jurors |
| `keycard::get_tasks_completed(addr)` | Task count |
| `jury::has_committed(room_id, addr)` | Commit status |
| `jury::has_revealed(room_id, addr)` | Reveal status |

---

## Quick Reference: Complete Deployment Commands

```bash
# 1. Navigate to project
cd /home/abdoulaahmad/Documents/aptos/aptosroom-protocol

# 2. Initialize account (if not done)
aptos init --network testnet

# 3. Fund account
aptos account fund-with-faucet --account default --amount 100000000

# 4. Update Move.toml with your address
# Edit: aptosroom = "YOUR_ADDRESS"

# 5. Compile
aptos move compile

# 6. Test
aptos move test

# 7. Deploy
aptos move publish --named-addresses aptosroom=default --assume-yes

# 8. Verify
aptos account list --query modules --account default

# 9. Test keycard creation
aptos move run --function-id default::keycard::mint --assume-yes
```

---

## Network Information

| Property | Value |
|----------|-------|
| Network | Aptos Testnet |
| Chain ID | 2 |
| REST API | https://fullnode.testnet.aptoslabs.com/v1 |
| Faucet | https://faucet.testnet.aptoslabs.com |
| Explorer | https://explorer.aptoslabs.com/?network=testnet |

---

## ✅ DEPLOYMENT COMPLETED — February 3, 2026

### Deployment Transaction
| Field | Value |
|-------|-------|
| **Transaction Hash** | `0x53d117618d9a4d5170eca70d0dc040871e15f5b0127044c00ef148eacf66c682` |
| **Contract Address** | `0x34a1f012718433e11b3515330d2d65093a13ffccc6b31883f490d653382eedcc` |
| **Network** | Testnet |
| **Gas Used** | 26,868 units |
| **Gas Cost** | ~0.0027 APT |
| **Package Size** | 48,423 bytes |
| **Status** | ✅ Executed successfully |

### Explorer Links
- **Deploy TX:** [View on Explorer](https://explorer.aptoslabs.com/txn/0x53d117618d9a4d5170eca70d0dc040871e15f5b0127044c00ef148eacf66c682?network=testnet)
- **Account:** [View on Explorer](https://explorer.aptoslabs.com/account/0x34a1f012718433e11b3515330d2d65093a13ffccc6b31883f490d653382eedcc?network=testnet)

### Deployed Modules
```
0x34a1f012718433e11b3515330d2d65093a13ffccc6b31883f490d653382eedcc::constants
0x34a1f012718433e11b3515330d2d65093a13ffccc6b31883f490d653382eedcc::errors
0x34a1f012718433e11b3515330d2d65093a13ffccc6b31883f490d653382eedcc::events
0x34a1f012718433e11b3515330d2d65093a13ffccc6b31883f490d653382eedcc::keycard
0x34a1f012718433e11b3515330d2d65093a13ffccc6b31883f490d653382eedcc::juror_registry
0x34a1f012718433e11b3515330d2d65093a13ffccc6b31883f490d653382eedcc::vault
0x34a1f012718433e11b3515330d2d65093a13ffccc6b31883f490d653382eedcc::room
0x34a1f012718433e11b3515330d2d65093a13ffccc6b31883f490d653382eedcc::jury
0x34a1f012718433e11b3515330d2d65093a13ffccc6b31883f490d653382eedcc::variance
0x34a1f012718433e11b3515330d2d65093a13ffccc6b31883f490d653382eedcc::aggregation
0x34a1f012718433e11b3515330d2d65093a13ffccc6b31883f490d653382eedcc::settlement
```

### Post-Deployment Verification (Completed)
- ✅ Keycard minted: TX `0xe1c2cec4c2b744a8c5aa8dea1c87269bff85fe74b641f05ef372d1c7d16363fd`
- ✅ View function tested: `vault::vault_exists` returns correctly
- ✅ Query function tested: `keycard::get_tasks_completed` returns `0`

---

## Next Steps After Deployment

1. ✅ Verify all modules deployed
2. ✅ Test basic functions (mint keycard, register juror)
3. ⏳ Create end-to-end test room
4. ⏳ Build TypeScript SDK for frontend
5. ⏳ Create React UI

---

**Document Version:** 1.1  
**Last Updated:** February 3, 2026  
**Author:** AptosRoom Protocol Team
