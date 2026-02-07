/**
 * Encryption utilities for commit-reveal voting
 * Uses NaCl Box (X25519 + XSalsa20 + Poly1305)
 */
import nacl from 'tweetnacl';
import ed2curve from 'ed2curve';
import type { TierVoteData, VoteData, EncryptedVotePackage } from '../types/index.js';
import { HashUtils } from './hash.js';

/**
 * Encryption utilities for vote data
 */
export class EncryptionUtils {
  /**
   * Convert Ed25519 public key to X25519 for encryption
   */
  static ed25519ToX25519PublicKey(ed25519PublicKey: Uint8Array): Uint8Array {
    const x25519Key = ed2curve.convertPublicKey(ed25519PublicKey);
    if (!x25519Key) {
      throw new Error('Failed to convert Ed25519 public key to X25519');
    }
    return x25519Key;
  }

  /**
   * Convert Ed25519 private key to X25519 for decryption
   */
  static ed25519ToX25519PrivateKey(ed25519PrivateKey: Uint8Array): Uint8Array {
    const x25519Key = ed2curve.convertSecretKey(ed25519PrivateKey);
    if (!x25519Key) {
      throw new Error('Failed to convert Ed25519 private key to X25519');
    }
    return x25519Key;
  }

  /**
   * Generate a random salt (32 bytes)
   */
  static generateSalt(): Uint8Array {
    return nacl.randomBytes(32);
  }

  /**
   * Generate an ephemeral keypair for encryption
   */
  static generateEphemeralKeyPair(): nacl.BoxKeyPair {
    return nacl.box.keyPair();
  }

  /**
   * Encrypt tier vote data for on-chain storage
   * 
   * Returns encrypted package containing:
   * - commitHash: SHA3-256 hash for commit verification
   * - encryptedData: Encrypted vote data (nonce + ciphertext)
   * - nonce: The nonce used (also prepended to encryptedData)
   */
  static encryptTierVote(
    tierA: string[],
    tierB: string[],
    recipientEd25519PublicKey: Uint8Array
  ): EncryptedVotePackage {
    // Generate random salt
    const salt = this.generateSalt();

    // Create vote data object
    const voteData: TierVoteData = { tierA, tierB, salt };

    // Serialize to JSON
    const plaintext = new TextEncoder().encode(JSON.stringify(voteData));

    // Generate ephemeral keypair for this encryption
    const ephemeralKeyPair = this.generateEphemeralKeyPair();

    // Convert recipient's Ed25519 public key to X25519
    const recipientX25519Key = this.ed25519ToX25519PublicKey(recipientEd25519PublicKey);

    // Generate nonce
    const nonce = nacl.randomBytes(nacl.box.nonceLength);

    // Encrypt using NaCl box
    const ciphertext = nacl.box(plaintext, nonce, recipientX25519Key, ephemeralKeyPair.secretKey);

    // Combine: ephemeral_public_key (32) + nonce (24) + ciphertext
    const encryptedData = new Uint8Array(32 + 24 + ciphertext.length);
    encryptedData.set(ephemeralKeyPair.publicKey, 0);
    encryptedData.set(nonce, 32);
    encryptedData.set(ciphertext, 56);

    // Compute commit hash
    const commitHash = HashUtils.computeTierVoteHash(tierA, tierB, salt);

    return {
      commitHash,
      encryptedData,
      nonce,
    };
  }

  /**
   * Decrypt tier vote data from on-chain storage
   */
  static decryptTierVote(
    encryptedData: Uint8Array,
    recipientEd25519PrivateKey: Uint8Array
  ): TierVoteData {
    if (encryptedData.length < 56) {
      throw new Error('Encrypted data too short');
    }

    // Extract components
    const ephemeralPublicKey = encryptedData.slice(0, 32);
    const nonce = encryptedData.slice(32, 56);
    const ciphertext = encryptedData.slice(56);

    // Convert recipient's Ed25519 private key to X25519
    const recipientX25519Key = this.ed25519ToX25519PrivateKey(recipientEd25519PrivateKey);

    // Decrypt using NaCl box.open
    const plaintext = nacl.box.open(ciphertext, nonce, ephemeralPublicKey, recipientX25519Key);

    if (!plaintext) {
      throw new Error('Decryption failed - invalid ciphertext or wrong key');
    }

    // Parse JSON
    const jsonString = new TextDecoder().decode(plaintext);
    const data = JSON.parse(jsonString) as TierVoteData;

    // Convert salt back to Uint8Array if it was serialized as array
    if (Array.isArray(data.salt)) {
      data.salt = new Uint8Array(data.salt);
    }

    return data;
  }

  /**
   * Encrypt standard vote data
   */
  static encryptVote(
    participant: string,
    score: number,
    recipientEd25519PublicKey: Uint8Array
  ): EncryptedVotePackage {
    const salt = this.generateSalt();
    const voteData: VoteData = { participant, score, salt };
    const plaintext = new TextEncoder().encode(JSON.stringify(voteData));

    const ephemeralKeyPair = this.generateEphemeralKeyPair();
    const recipientX25519Key = this.ed25519ToX25519PublicKey(recipientEd25519PublicKey);
    const nonce = nacl.randomBytes(nacl.box.nonceLength);

    const ciphertext = nacl.box(plaintext, nonce, recipientX25519Key, ephemeralKeyPair.secretKey);

    const encryptedData = new Uint8Array(32 + 24 + ciphertext.length);
    encryptedData.set(ephemeralKeyPair.publicKey, 0);
    encryptedData.set(nonce, 32);
    encryptedData.set(ciphertext, 56);

    const commitHash = HashUtils.computeVoteHash(participant, score, salt);

    return {
      commitHash,
      encryptedData,
      nonce,
    };
  }

  /**
   * Decrypt standard vote data
   */
  static decryptVote(
    encryptedData: Uint8Array,
    recipientEd25519PrivateKey: Uint8Array
  ): VoteData {
    if (encryptedData.length < 56) {
      throw new Error('Encrypted data too short');
    }

    const ephemeralPublicKey = encryptedData.slice(0, 32);
    const nonce = encryptedData.slice(32, 56);
    const ciphertext = encryptedData.slice(56);

    const recipientX25519Key = this.ed25519ToX25519PrivateKey(recipientEd25519PrivateKey);
    const plaintext = nacl.box.open(ciphertext, nonce, ephemeralPublicKey, recipientX25519Key);

    if (!plaintext) {
      throw new Error('Decryption failed');
    }

    const data = JSON.parse(new TextDecoder().decode(plaintext)) as VoteData;
    if (Array.isArray(data.salt)) {
      data.salt = new Uint8Array(data.salt);
    }

    return data;
  }

  /**
   * Verify that decrypted data matches commit hash
   */
  static verifyTierVoteCommit(
    voteData: TierVoteData,
    expectedHash: Uint8Array
  ): boolean {
    const computedHash = HashUtils.computeTierVoteHash(
      voteData.tierA,
      voteData.tierB,
      voteData.salt
    );
    return HashUtils.hashesEqual(computedHash, expectedHash);
  }

  /**
   * Verify standard vote commit
   */
  static verifyVoteCommit(
    voteData: VoteData,
    expectedHash: Uint8Array
  ): boolean {
    const computedHash = HashUtils.computeVoteHash(
      voteData.participant,
      voteData.score,
      voteData.salt
    );
    return HashUtils.hashesEqual(computedHash, expectedHash);
  }
}
