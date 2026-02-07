# On-Chain Encrypted Commit-Reveal Implementation

**Version:** 1.0  
**Date:** February 7, 2026  
**Status:** Proposed

---

## Table of Contents

1. [Overview](#overview)
2. [Problem Statement](#problem-statement)
3. [Solution Architecture](#solution-architecture)
4. [Contract Changes](#contract-changes)
5. [TypeScript SDK](#typescript-sdk)
6. [Frontend Integration](#frontend-integration)
7. [Security Considerations](#security-considerations)
8. [Gas Cost Analysis](#gas-cost-analysis)
9. [Implementation Checklist](#implementation-checklist)

---

## Overview

This document describes **Option B: On-Chain Encrypted Storage** - a UX improvement to the commit-reveal voting scheme that eliminates the need for users to save vote data locally.

### Current Problem

The existing commit-reveal requires users to:
1. Save `tier_a`, `tier_b`, and `salt` values locally after commit
2. Retrieve these values during reveal phase
3. If data is lost → user cannot reveal → excluded from settlement

### Solution

Store encrypted vote data on-chain during commit. Only the user (with their private key) can decrypt during reveal.

---

## Problem Statement

### Current Commit-Reveal Flow

```
COMMIT:
  hash = sha3(tier_a + tier_b + salt)
  submit(hash)
  → User must save {tier_a, tier_b, salt} locally ❌

REVEAL:
  submit(tier_a, tier_b, salt)
  → If user lost data, they cannot reveal ❌
```

### Issues

| Problem | Impact |
|---------|--------|
| LocalStorage can be cleared | Data loss |
| Different device | Cannot reveal |
| Browser crash during commit | Data loss |
| User confusion | Bad UX |

---

## Solution Architecture

### Improved Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                         COMMIT PHASE                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Frontend:                                                      │
│  1. User selects tier assignments                               │
│  2. Generate random salt                                        │
│  3. Create payload: { tier_a, tier_b, salt }                    │
│  4. Encrypt payload with user's public key                      │
│  5. Compute commit hash                                         │
│  6. Submit both hash AND encrypted blob to contract             │
│                                                                 │
│  Contract stores:                                               │
│  - commit_hash: vector<u8>                                      │
│  - encrypted_data: vector<u8>  ← NEW                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         REVEAL PHASE                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Frontend (any device with same wallet):                        │
│  1. Fetch encrypted_data from contract                          │
│  2. Decrypt with user's wallet (private key)                    │
│  3. Extract { tier_a, tier_b, salt }                            │
│  4. Submit reveal transaction                                   │
│                                                                 │
│  ✅ User never needs to save anything!                           │
│  ✅ Works across devices!                                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Contract Changes

### 1. New Struct: TierVoteCommit

**File:** `sources/room.move`

```move
/// Tier vote commit with encrypted data for recovery
struct TierVoteCommit has store, drop, copy {
    /// SHA3-256 hash of vote (for verification)
    commit_hash: vector<u8>,
    /// Encrypted vote data (user can decrypt with their private key)
    encrypted_data: vector<u8>,
}
```

### 2. Update Room Struct

**File:** `sources/room.move`

```move
struct Room has key, store {
    // ... existing fields ...
    
    // BEFORE:
    // tier_vote_commits: SimpleMap<address, vector<u8>>,
    
    // AFTER:
    tier_vote_commits: SimpleMap<address, TierVoteCommit>,
}
```

### 3. Modified commit_tier_vote Function

**File:** `sources/jury.move`

```move
/// Commit tier vote with encrypted recovery data
/// 
/// # Arguments
/// * `account` - Juror's signer
/// * `room_id` - Room identifier
/// * `commit_hash` - SHA3-256 hash of (tier_a || tier_b || salt)
/// * `encrypted_data` - Encrypted vote data for recovery
public entry fun commit_tier_vote(
    account: &signer,
    room_id: u64,
    commit_hash: vector<u8>,
    encrypted_data: vector<u8>,
) {
    let juror = signer::address_of(account);

    // Validate room state
    let state = room::get_state(room_id);
    assert!(state == constants::STATE_JURY_ACTIVE(), errors::E_NOT_IN_COMMIT_PHASE());

    // Validate juror
    assert!(room::is_juror(room_id, juror), errors::E_NOT_JUROR());
    assert!(!room::has_committed_tier_vote(room_id, juror), errors::E_ALREADY_COMMITTED());

    // Validate encrypted data size (prevent abuse)
    assert!(
        vector::length(&encrypted_data) <= constants::MAX_ENCRYPTED_DATA_SIZE(),
        errors::E_ENCRYPTED_DATA_TOO_LARGE()
    );

    // Store commit with encrypted data
    room::add_tier_vote_commit_with_encrypted(
        room_id, 
        juror, 
        commit_hash, 
        encrypted_data
    );

    // Emit event
    event::emit(TierVoteCommitted {
        room_id,
        juror,
        commit_hash,
        timestamp: timestamp::now_seconds(),
    });
}
```

### 4. New Constants

**File:** `sources/constants.move`

```move
/// Maximum size for encrypted vote data (1KB)
public fun MAX_ENCRYPTED_DATA_SIZE(): u64 { 1024 }
```

### 5. New Error Code

**File:** `sources/errors.move`

```move
/// Encrypted data exceeds maximum size
public fun E_ENCRYPTED_DATA_TOO_LARGE(): u64 { 25 }
```

### 6. New View Function

**File:** `sources/jury.move`

```move
/// Get encrypted vote data for a juror (for recovery during reveal)
#[view]
public fun get_tier_vote_encrypted(room_id: u64, juror: address): vector<u8> {
    room::get_tier_vote_encrypted_data(room_id, juror)
}
```

### 7. Room Module Helper Functions

**File:** `sources/room.move`

```move
/// Add tier vote commit with encrypted data
public(friend) fun add_tier_vote_commit_with_encrypted(
    room_id: u64,
    juror: address,
    commit_hash: vector<u8>,
    encrypted_data: vector<u8>,
) acquires RoomRegistry {
    let registry = borrow_global_mut<RoomRegistry>(@aptosroom);
    let room = smart_table::borrow_mut(&mut registry.rooms, room_id);
    
    let commit = TierVoteCommit {
        commit_hash,
        encrypted_data,
    };
    
    simple_map::add(&mut room.tier_vote_commits, juror, commit);
}

/// Get encrypted data for a juror's tier vote
public fun get_tier_vote_encrypted_data(room_id: u64, juror: address): vector<u8> 
acquires RoomRegistry {
    let registry = borrow_global<RoomRegistry>(@aptosroom);
    let room = smart_table::borrow(&registry.rooms, room_id);
    let commit = simple_map::borrow(&room.tier_vote_commits, &juror);
    commit.encrypted_data
}

/// Get commit hash for verification (updated for new struct)
public fun get_tier_vote_commit(room_id: u64, juror: address): vector<u8> 
acquires RoomRegistry {
    let registry = borrow_global<RoomRegistry>(@aptosroom);
    let room = smart_table::borrow(&registry.rooms, room_id);
    let commit = simple_map::borrow(&room.tier_vote_commits, &juror);
    commit.commit_hash
}
```

---

## TypeScript SDK

### Installation

```bash
npm install @aptos-labs/ts-sdk tweetnacl ed2curve @noble/hashes
```

### Encryption Module

**File:** `sdk/src/encryption.ts`

```typescript
import nacl from 'tweetnacl';
import { convertPublicKey, convertSecretKey } from 'ed2curve';
import { sha3_256 } from '@noble/hashes/sha3';
import { BCS, TxnBuilderTypes } from '@aptos-labs/ts-sdk';

export interface TierVote {
  tierA: string[];
  tierB: string[];
  salt: Uint8Array;
}

export interface CommitData {
  commitHash: Uint8Array;
  encryptedData: Uint8Array;
  // Keep internally for validation (optional)
  vote: TierVote;
}

/**
 * Encryption utilities for tier vote commit-reveal
 */
export class TierVoteEncryption {
  
  /**
   * Create encrypted commit for tier vote
   * 
   * @param tierA - Addresses for Tier A
   * @param tierB - Addresses for Tier B
   * @param publicKey - User's Ed25519 public key (from wallet)
   * @returns CommitData with hash and encrypted blob
   */
  static createCommit(
    tierA: string[],
    tierB: string[],
    publicKey: Uint8Array
  ): CommitData {
    // 1. Generate random salt (32 bytes)
    const salt = nacl.randomBytes(32);
    
    // 2. Create vote object
    const vote: TierVote = { tierA, tierB, salt };
    
    // 3. Serialize vote for encryption
    const voteBytes = this.serializeVote(vote);
    
    // 4. Convert Ed25519 public key to X25519 for encryption
    const x25519PubKey = convertPublicKey(publicKey);
    if (!x25519PubKey) {
      throw new Error('Failed to convert public key');
    }
    
    // 5. Generate ephemeral keypair for encryption
    const ephemeral = nacl.box.keyPair();
    
    // 6. Encrypt vote data
    const nonce = nacl.randomBytes(24);
    const encrypted = nacl.box(voteBytes, nonce, x25519PubKey, ephemeral.secretKey);
    
    // 7. Package encrypted data: ephemeralPubKey (32) + nonce (24) + ciphertext
    const encryptedData = new Uint8Array(32 + 24 + encrypted.length);
    encryptedData.set(ephemeral.publicKey, 0);
    encryptedData.set(nonce, 32);
    encryptedData.set(encrypted, 56);
    
    // 8. Compute commit hash (same as contract)
    const commitHash = this.computeCommitHash(tierA, tierB, salt);
    
    return { commitHash, encryptedData, vote };
  }
  
  /**
   * Decrypt vote data for reveal
   * 
   * @param encryptedData - Encrypted blob from chain
   * @param secretKey - User's Ed25519 secret key
   * @returns Decrypted TierVote
   */
  static decryptVote(
    encryptedData: Uint8Array,
    secretKey: Uint8Array
  ): TierVote {
    // 1. Extract components
    const ephemeralPubKey = encryptedData.slice(0, 32);
    const nonce = encryptedData.slice(32, 56);
    const ciphertext = encryptedData.slice(56);
    
    // 2. Convert Ed25519 secret key to X25519
    const x25519SecretKey = convertSecretKey(secretKey);
    if (!x25519SecretKey) {
      throw new Error('Failed to convert secret key');
    }
    
    // 3. Decrypt
    const voteBytes = nacl.box.open(ciphertext, nonce, ephemeralPubKey, x25519SecretKey);
    if (!voteBytes) {
      throw new Error('Decryption failed - invalid key or corrupted data');
    }
    
    // 4. Deserialize vote
    return this.deserializeVote(voteBytes);
  }
  
  /**
   * Compute commit hash (must match contract implementation)
   */
  static computeCommitHash(
    tierA: string[],
    tierB: string[],
    salt: Uint8Array
  ): Uint8Array {
    // Serialize using BCS (same as Move contract)
    const serializer = new BCS.Serializer();
    
    // Serialize tier_a as vector<address>
    serializer.serializeU32AsUleb128(tierA.length);
    for (const addr of tierA) {
      serializer.serializeFixedBytes(hexToBytes(addr));
    }
    const tierABytes = serializer.getBytes();
    
    // Serialize tier_b as vector<address>
    const serializer2 = new BCS.Serializer();
    serializer2.serializeU32AsUleb128(tierB.length);
    for (const addr of tierB) {
      serializer2.serializeFixedBytes(hexToBytes(addr));
    }
    const tierBBytes = serializer2.getBytes();
    
    // Concatenate: tierA || tierB || salt
    const data = new Uint8Array(tierABytes.length + tierBBytes.length + salt.length);
    data.set(tierABytes, 0);
    data.set(tierBBytes, tierABytes.length);
    data.set(salt, tierABytes.length + tierBBytes.length);
    
    // Return SHA3-256 hash
    return sha3_256(data);
  }
  
  /**
   * Serialize vote for encryption
   */
  private static serializeVote(vote: TierVote): Uint8Array {
    const json = JSON.stringify({
      tierA: vote.tierA,
      tierB: vote.tierB,
      salt: Array.from(vote.salt),
    });
    return new TextEncoder().encode(json);
  }
  
  /**
   * Deserialize vote from encrypted data
   */
  private static deserializeVote(bytes: Uint8Array): TierVote {
    const json = new TextDecoder().decode(bytes);
    const parsed = JSON.parse(json);
    return {
      tierA: parsed.tierA,
      tierB: parsed.tierB,
      salt: new Uint8Array(parsed.salt),
    };
  }
}

// Helper function
function hexToBytes(hex: string): Uint8Array {
  const cleanHex = hex.startsWith('0x') ? hex.slice(2) : hex;
  const bytes = new Uint8Array(cleanHex.length / 2);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = parseInt(cleanHex.substr(i * 2, 2), 16);
  }
  return bytes;
}
```

### Contract Client

**File:** `sdk/src/client.ts`

```typescript
import { Aptos, AptosConfig, Network, Account } from '@aptos-labs/ts-sdk';
import { TierVoteEncryption } from './encryption';

export class AptosRoomClient {
  private aptos: Aptos;
  private contractAddress: string;
  
  constructor(network: Network = Network.TESTNET) {
    const config = new AptosConfig({ network });
    this.aptos = new Aptos(config);
    this.contractAddress = '0x2bf0af3ddc84bf1d6d32e0961a678cca4cd49f4f3a79b5b9d3b892bbfa6cc455';
  }
  
  /**
   * Commit tier vote with encrypted recovery data
   */
  async commitTierVote(
    account: Account,
    roomId: number,
    tierA: string[],
    tierB: string[]
  ): Promise<string> {
    // Create encrypted commit
    const publicKey = account.publicKey.toUint8Array();
    const { commitHash, encryptedData } = TierVoteEncryption.createCommit(
      tierA,
      tierB,
      publicKey
    );
    
    // Submit transaction
    const txn = await this.aptos.transaction.build.simple({
      sender: account.accountAddress,
      data: {
        function: `${this.contractAddress}::jury::commit_tier_vote`,
        functionArguments: [
          roomId,
          Array.from(commitHash),
          Array.from(encryptedData),
        ],
      },
    });
    
    const pendingTxn = await this.aptos.signAndSubmitTransaction({
      signer: account,
      transaction: txn,
    });
    
    return pendingTxn.hash;
  }
  
  /**
   * Fetch encrypted vote data from chain
   */
  async getEncryptedVote(roomId: number, juror: string): Promise<Uint8Array> {
    const result = await this.aptos.view({
      payload: {
        function: `${this.contractAddress}::jury::get_tier_vote_encrypted`,
        functionArguments: [roomId, juror],
      },
    });
    
    return new Uint8Array(result[0] as number[]);
  }
  
  /**
   * Reveal tier vote (auto-decrypts from chain)
   */
  async revealTierVote(
    account: Account,
    roomId: number
  ): Promise<string> {
    // 1. Fetch encrypted data from chain
    const encryptedData = await this.getEncryptedVote(
      roomId,
      account.accountAddress.toString()
    );
    
    // 2. Decrypt with user's private key
    const secretKey = account.privateKey.toUint8Array();
    const vote = TierVoteEncryption.decryptVote(encryptedData, secretKey);
    
    // 3. Submit reveal transaction
    const txn = await this.aptos.transaction.build.simple({
      sender: account.accountAddress,
      data: {
        function: `${this.contractAddress}::jury::reveal_tier_vote`,
        functionArguments: [
          roomId,
          vote.tierA,
          vote.tierB,
          Array.from(vote.salt),
        ],
      },
    });
    
    const pendingTxn = await this.aptos.signAndSubmitTransaction({
      signer: account,
      transaction: txn,
    });
    
    return pendingTxn.hash;
  }
}
```

---

## Frontend Integration

### React Hook

**File:** `frontend/src/hooks/useTierVote.ts`

```typescript
import { useWallet } from "@aptos-labs/wallet-adapter-react";
import { useState } from "react";
import { TierVoteEncryption } from "@aptosroom/sdk";

export function useTierVote(roomId: number) {
  const { account, signAndSubmitTransaction } = useWallet();
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  
  const commitVote = async (tierA: string[], tierB: string[]) => {
    if (!account?.publicKey) {
      setError("Wallet not connected");
      return;
    }
    
    setLoading(true);
    setError(null);
    
    try {
      // Create encrypted commit
      const publicKey = hexToBytes(account.publicKey);
      const { commitHash, encryptedData } = TierVoteEncryption.createCommit(
        tierA,
        tierB,
        publicKey
      );
      
      // Submit transaction
      await signAndSubmitTransaction({
        data: {
          function: `${CONTRACT_ADDRESS}::jury::commit_tier_vote`,
          functionArguments: [roomId, commitHash, encryptedData],
        },
      });
      
      return true;
    } catch (err) {
      setError(err.message);
      return false;
    } finally {
      setLoading(false);
    }
  };
  
  const revealVote = async () => {
    // Frontend fetches encrypted data and prompts wallet to decrypt
    // Implementation depends on wallet's decrypt API support
  };
  
  return { commitVote, revealVote, loading, error };
}
```

### Component Example

**File:** `frontend/src/components/TierVoting.tsx`

```tsx
import { useTierVote } from "../hooks/useTierVote";

export function TierVoting({ roomId, contributors }) {
  const { commitVote, loading, error } = useTierVote(roomId);
  const [tierA, setTierA] = useState<string[]>([]);
  const [tierB, setTierB] = useState<string[]>([]);
  
  const handleSubmit = async () => {
    const success = await commitVote(tierA, tierB);
    if (success) {
      // Show success message
      // No need to save anything locally!
    }
  };
  
  return (
    <div>
      <h2>Rank Contributors</h2>
      
      <div>
        <h3>Tier A (Top Performers)</h3>
        {/* Drag and drop interface */}
      </div>
      
      <div>
        <h3>Tier B (Good Performers)</h3>
        {/* Drag and drop interface */}
      </div>
      
      <button onClick={handleSubmit} disabled={loading}>
        {loading ? "Submitting..." : "Submit Vote"}
      </button>
      
      {error && <p className="error">{error}</p>}
      
      <p className="info">
        ✅ Your vote is encrypted and stored on-chain.
        You can reveal from any device with your wallet.
      </p>
    </div>
  );
}
```

---

## Security Considerations

### Encryption Security

| Aspect | Implementation |
|--------|----------------|
| **Algorithm** | NaCl Box (X25519 + XSalsa20 + Poly1305) |
| **Key Derivation** | Ed25519 → X25519 conversion |
| **Nonce** | Random 24 bytes per encryption |
| **Ephemeral Keys** | New keypair per commit |

### Attack Vectors

| Attack | Mitigation |
|--------|------------|
| **Brute force decryption** | 256-bit keys, computationally infeasible |
| **Replay attack** | Commit hash verified on-chain |
| **Vote tampering** | Hash verification during reveal |
| **Storage abuse** | Max encrypted size limit (1KB) |
| **Key extraction** | Private key never leaves wallet |

### Privacy Guarantees

- ✅ Vote content hidden until reveal phase
- ✅ Only vote owner can decrypt
- ✅ Contract never sees unencrypted vote during commit
- ⚠️ Vote revealed on-chain during reveal (public)

---

## Gas Cost Analysis

### Storage Costs

| Component | Size | Cost (estimate) |
|-----------|------|-----------------|
| Commit hash | 32 bytes | ~0.0005 APT |
| Encrypted data (small) | ~170 bytes | ~0.002 APT |
| Encrypted data (large) | ~500 bytes | ~0.005 APT |

### Comparison: Before vs After

| Scenario | Without Encryption | With Encryption |
|----------|-------------------|-----------------|
| Commit | ~0.001 APT | ~0.003 APT |
| Reveal | ~0.002 APT | ~0.002 APT |
| **Total** | ~0.003 APT | ~0.005 APT |

**Extra cost per vote:** ~0.002 APT (~$0.02 at $10/APT)

---

## Implementation Checklist

### Contract Changes

- [ ] Add `TierVoteCommit` struct with `encrypted_data` field
- [ ] Update `Room` struct to use new commit type
- [ ] Modify `commit_tier_vote` to accept encrypted data
- [ ] Add `MAX_ENCRYPTED_DATA_SIZE` constant
- [ ] Add `E_ENCRYPTED_DATA_TOO_LARGE` error
- [ ] Add `get_tier_vote_encrypted` view function
- [ ] Update `add_tier_vote_commit` helper
- [ ] Update `get_tier_vote_commit` helper
- [ ] Update all tests for new signature

### SDK Development

- [ ] Create encryption module
- [ ] Implement `createCommit` function
- [ ] Implement `decryptVote` function
- [ ] Implement `computeCommitHash` function
- [ ] Create contract client
- [ ] Add unit tests for encryption
- [ ] Add integration tests

### Frontend Integration

- [ ] Add SDK dependency
- [ ] Create `useTierVote` hook
- [ ] Update commit UI (remove local storage)
- [ ] Update reveal UI (auto-decrypt)
- [ ] Add wallet decryption support check

### Testing

- [ ] Unit tests for encryption/decryption
- [ ] Contract tests with encrypted data
- [ ] E2E test: commit → reveal across devices
- [ ] Gas cost benchmarks

---

## Appendix: Wallet Decryption Support

### Wallet APIs

| Wallet | Decrypt API | Status |
|--------|------------|--------|
| Petra | `window.petra.decrypt()` | Experimental |
| Pontem | Not supported | - |
| Martian | Not supported | - |

### Fallback: Manual Key Access

If wallet doesn't support decrypt, user can export private key and SDK decrypts client-side. This is less secure but works universally.

```typescript
// Fallback for wallets without decrypt API
const decryptWithPrivateKey = async (encryptedData: Uint8Array) => {
  // Prompt user to paste private key (not recommended for production)
  const privateKey = prompt("Enter private key to decrypt");
  return TierVoteEncryption.decryptVote(encryptedData, hexToBytes(privateKey));
};
```

### Recommended: Keyless Account

Aptos Keyless accounts may provide better decryption UX in the future.

---

## References

- [Aptos TypeScript SDK](https://aptos.dev/sdks/ts-sdk/)
- [NaCl Cryptography](https://nacl.cr.yp.to/box.html)
- [Ed25519 to X25519 Conversion](https://github.com/nickolasburr/ed2curve)
- [BCS Serialization](https://github.com/aptos-labs/bcs)
