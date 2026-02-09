/**
 * Jury Module Client
 * Handles voting (commit/reveal) for both standard and tier voting
 */
import {
  Aptos,
  Account,
  type PendingTransactionResponse,
  type InputGenerateTransactionPayloadData,
} from '@aptos-labs/ts-sdk';
import { HashUtils } from '../utils/hash.js';
import { EncryptionUtils } from '../utils/encryption.js';
import nacl from 'tweetnacl';

export interface CommitVoteParams {
  roomId: number;
  contributor: string;
  voteHash: Uint8Array;
}

export interface RevealVoteParams {
  roomId: number;
  contributor: string;
  score: number;
  salt: Uint8Array;
}

export interface CommitTierVoteParams {
  roomId: number;
  voteHash: Uint8Array;
  encryptedData: Uint8Array;
}

export interface RevealTierVoteParams {
  roomId: number;
  tierA: string[];  // Addresses selected for Tier A
  tierB: string[];  // Addresses selected for Tier B
  salt: Uint8Array;
}

export interface TierVoteData {
  tierA: string[];
  tierB: string[];
  salt: Uint8Array;
}

export class JuryClient {
  constructor(
    private readonly aptos: Aptos,
    private readonly moduleAddress: string
  ) { }

  // ============================================================
  // HELPER FUNCTIONS
  // ============================================================

  /**
   * Compute vote hash for standard voting
   */
  computeVoteHash(contributor: string, score: number, salt: Uint8Array): Uint8Array {
    return HashUtils.computeVoteHash(contributor, score, salt);
  }

  /**
   * Compute vote hash for tier voting (tierA/tierB format)
   * Must match jury.move::compute_tier_commit_hash()
   * Format: BCS(tierA) || BCS(tierB) || salt
   */
  computeTierVoteHash(tierA: string[], tierB: string[], salt: Uint8Array): Uint8Array {
    return HashUtils.computeTierVoteHash(tierA, tierB, salt);
  }

  /**
   * Encrypt tier vote data for on-chain storage
   * Uses the juror's Ed25519 public key for encryption
   * TierVoteData now contains tierA and tierB arrays
   */
  encryptTierVote(
    voteData: TierVoteData,
    jurorEd25519PublicKey: Uint8Array
  ): Uint8Array {
    // Serialize vote data (now with tierA/tierB)
    const plaintext = new TextEncoder().encode(JSON.stringify(voteData));

    // Generate ephemeral keypair
    const ephemeralKeyPair = nacl.box.keyPair();

    // Convert Ed25519 to X25519
    const recipientX25519Key = EncryptionUtils.ed25519ToX25519PublicKey(jurorEd25519PublicKey);

    // Generate nonce
    const nonce = nacl.randomBytes(nacl.box.nonceLength);

    // Encrypt with NaCl box
    const ciphertext = nacl.box(plaintext, nonce, recipientX25519Key, ephemeralKeyPair.secretKey);

    // Package: ephemeral public key (32) + nonce (24) + ciphertext
    const result = new Uint8Array(32 + 24 + ciphertext.length);
    result.set(ephemeralKeyPair.publicKey, 0);
    result.set(nonce, 32);
    result.set(ciphertext, 56);

    return result;
  }

  // ============================================================
  // ENTRY FUNCTIONS - STANDARD VOTING
  // ============================================================

  /**
   * Commit a standard vote for a contributor
   */
  async commitVote(
    account: Account,
    params: CommitVoteParams
  ): Promise<PendingTransactionResponse> {
    const payload: InputGenerateTransactionPayloadData = {
      function: `${this.moduleAddress}::jury::commit_vote`,
      functionArguments: [
        BigInt(params.roomId),
        params.contributor,
        Array.from(params.voteHash),
      ],
    };

    const tx = await this.aptos.transaction.build.simple({
      sender: account.accountAddress,
      data: payload,
    });

    const signedTx = await this.aptos.transaction.sign({
      signer: account,
      transaction: tx,
    });

    return await this.aptos.transaction.submit.simple({
      senderAuthenticator: signedTx,
      transaction: tx,
    });
  }

  /**
   * Reveal a standard vote
   */
  async revealVote(
    account: Account,
    params: RevealVoteParams
  ): Promise<PendingTransactionResponse> {
    const payload: InputGenerateTransactionPayloadData = {
      function: `${this.moduleAddress}::jury::reveal_vote`,
      functionArguments: [
        BigInt(params.roomId),
        params.contributor,
        BigInt(params.score),
        Array.from(params.salt),
      ],
    };

    const tx = await this.aptos.transaction.build.simple({
      sender: account.accountAddress,
      data: payload,
    });

    const signedTx = await this.aptos.transaction.sign({
      signer: account,
      transaction: tx,
    });

    return await this.aptos.transaction.submit.simple({
      senderAuthenticator: signedTx,
      transaction: tx,
    });
  }

  // ============================================================
  // ENTRY FUNCTIONS - TIER VOTING
  // ============================================================

  /**
   * Commit a tier vote (ordered ranking of all contributors)
   * Stores encrypted data on-chain for UX improvement
   */
  async commitTierVote(
    account: Account,
    params: CommitTierVoteParams
  ): Promise<PendingTransactionResponse> {
    const payload: InputGenerateTransactionPayloadData = {
      function: `${this.moduleAddress}::jury::commit_tier_vote`,
      functionArguments: [
        BigInt(params.roomId),
        Array.from(params.voteHash),
        Array.from(params.encryptedData),
      ],
    };

    const tx = await this.aptos.transaction.build.simple({
      sender: account.accountAddress,
      data: payload,
    });

    const signedTx = await this.aptos.transaction.sign({
      signer: account,
      transaction: tx,
    });

    return await this.aptos.transaction.submit.simple({
      senderAuthenticator: signedTx,
      transaction: tx,
    });
  }

  /**
   * Reveal a tier vote
   * Provides tier_a and tier_b selections to the contract
   */
  async revealTierVote(
    account: Account,
    params: RevealTierVoteParams
  ): Promise<PendingTransactionResponse> {
    const payload: InputGenerateTransactionPayloadData = {
      function: `${this.moduleAddress}::jury::reveal_tier_vote`,
      functionArguments: [
        BigInt(params.roomId),
        params.tierA,
        params.tierB,
        Array.from(params.salt),
      ],
    };

    const tx = await this.aptos.transaction.build.simple({
      sender: account.accountAddress,
      data: payload,
    });

    const signedTx = await this.aptos.transaction.sign({
      signer: account,
      transaction: tx,
    });

    return await this.aptos.transaction.submit.simple({
      senderAuthenticator: signedTx,
      transaction: tx,
    });
  }

  // ============================================================
  // VIEW FUNCTIONS - STANDARD VOTING
  // ============================================================

  /**
   * Check if juror has committed a vote for contributor
   */
  async hasCommittedVote(
    roomId: number,
    juror: string,
    contributor: string
  ): Promise<boolean> {
    const result = await this.aptos.view({
      payload: {
        function: `${this.moduleAddress}::jury::has_committed_vote`,
        functionArguments: [BigInt(roomId), juror, contributor],
      },
    });
    return result[0] as boolean;
  }

  /**
   * Check if juror has revealed a vote for contributor
   */
  async hasRevealedVote(
    roomId: number,
    juror: string,
    contributor: string
  ): Promise<boolean> {
    const result = await this.aptos.view({
      payload: {
        function: `${this.moduleAddress}::jury::has_revealed_vote`,
        functionArguments: [BigInt(roomId), juror, contributor],
      },
    });
    return result[0] as boolean;
  }

  /**
   * Get revealed vote score
   */
  async getVoteScore(
    roomId: number,
    juror: string,
    contributor: string
  ): Promise<number> {
    const result = await this.aptos.view({
      payload: {
        function: `${this.moduleAddress}::jury::get_vote_score`,
        functionArguments: [BigInt(roomId), juror, contributor],
      },
    });
    return Number(result[0]);
  }

  // ============================================================
  // VIEW FUNCTIONS - TIER VOTING
  // ============================================================

  /**
   * Check if juror has committed a tier vote
   */
  async hasTierVote(roomId: number, juror: string): Promise<boolean> {
    const result = await this.aptos.view({
      payload: {
        function: `${this.moduleAddress}::jury::has_tier_vote`,
        functionArguments: [BigInt(roomId), juror],
      },
    });
    return result[0] as boolean;
  }

  /**
   * Check if tier vote has been revealed
   */
  async isTierVoteRevealed(roomId: number, juror: string): Promise<boolean> {
    const result = await this.aptos.view({
      payload: {
        function: `${this.moduleAddress}::jury::is_tier_vote_revealed`,
        functionArguments: [BigInt(roomId), juror],
      },
    });
    return result[0] as boolean;
  }

  /**
   * Get tier vote hash (for verification)
   */
  async getTierVoteHash(roomId: number, juror: string): Promise<Uint8Array> {
    const result = await this.aptos.view({
      payload: {
        function: `${this.moduleAddress}::jury::get_tier_vote_hash`,
        functionArguments: [BigInt(roomId), juror],
      },
    });
    return new Uint8Array(result[0] as number[]);
  }

  /**
   * Get encrypted tier vote data
   */
  async getTierVoteEncrypted(roomId: number, juror: string): Promise<Uint8Array> {
    const result = await this.aptos.view({
      payload: {
        function: `${this.moduleAddress}::jury::get_tier_vote_encrypted`,
        functionArguments: [BigInt(roomId), juror],
      },
    });
    return new Uint8Array(result[0] as number[]);
  }

  /**
   * Get revealed tier vote ordering
   */
  async getTierVoteOrdering(roomId: number, juror: string): Promise<string[]> {
    const result = await this.aptos.view({
      payload: {
        function: `${this.moduleAddress}::jury::get_tier_vote_ordering`,
        functionArguments: [BigInt(roomId), juror],
      },
    });
    return result[0] as string[];
  }

  /**
   * Get tier commit count for room
   */
  async getTierCommitCount(roomId: number): Promise<number> {
    const result = await this.aptos.view({
      payload: {
        function: `${this.moduleAddress}::jury::get_tier_commit_count`,
        functionArguments: [BigInt(roomId)],
      },
    });
    return Number(result[0]);
  }

  /**
   * Get tier reveal count for room
   */
  async getTierRevealCount(roomId: number): Promise<number> {
    const result = await this.aptos.view({
      payload: {
        function: `${this.moduleAddress}::jury::get_tier_reveal_count`,
        functionArguments: [BigInt(roomId)],
      },
    });
    return Number(result[0]);
  }
}
