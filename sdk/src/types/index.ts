/**
 * Core types for AptosRoom SDK
 */

// Re-export commonly used Aptos types
export type { Account, AccountAddress, PendingTransactionResponse } from '@aptos-labs/ts-sdk';

/**
 * Room structure as returned from contract
 */
export interface Room {
  id: bigint;
  client: string;
  state: number;
  category: string;
  description: string;
  prizePool: bigint;
  currentJurors: number;
  requiredJurors: number;
  entries: Entry[];
  createdAt: bigint;
}

/**
 * Entry submission
 */
export interface Entry {
  participant: string;
  contentHash: Uint8Array;
  submittedAt: bigint;
  clientScore?: number;
}

/**
 * Juror information
 */
export interface Juror {
  address: string;
  hasCommitted: boolean;
  hasRevealed: boolean;
}

/**
 * Keycard NFT
 */
export interface Keycard {
  owner: string;
  tokenId: string;
  mintedAt: bigint;
}

/**
 * Juror registration
 */
export interface JurorRegistration {
  juror: string;
  categories: string[];
  registeredAt: bigint;
  reputation: number;
}

/**
 * Tier vote structure
 */
export interface TierVote {
  commitHash: Uint8Array;
  encryptedData: Uint8Array;
  revealed: boolean;
  tierA: string[];
  tierB: string[];
}

/**
 * Tier vote commit data (for encryption/decryption)
 */
export interface TierVoteData {
  tierA: string[];
  tierB: string[];
  salt: Uint8Array;
}

/**
 * Vote commit data
 */
export interface VoteData {
  score: number;
  participant: string;
  salt: Uint8Array;
}

/**
 * Settlement info
 */
export interface Settlement {
  roomId: bigint;
  approved: boolean;
  executed: boolean;
  totalPrize: bigint;
  payouts: Payout[];
}

/**
 * Individual payout
 */
export interface Payout {
  recipient: string;
  amount: bigint;
  tier?: number;
}

/**
 * Transaction result
 */
export interface TxResult {
  hash: string;
  success: boolean;
  gasUsed: bigint;
  version: bigint;
}

/**
 * Room creation parameters
 */
export interface CreateRoomParams {
  category: string;
  description: string;
  requiredJurors: number;
  prizePoolAmount: bigint;
}

/**
 * Tier vote commit parameters
 */
export interface CommitTierVoteParams {
  roomId: bigint;
  tierA: string[];
  tierB: string[];
}

/**
 * Standard vote commit parameters
 */
export interface CommitVoteParams {
  roomId: bigint;
  participant: string;
  score: number;
}

/**
 * View function result wrapper
 */
export interface ViewResult<T> {
  data: T;
  success: boolean;
  error?: string;
}

/**
 * Encrypted vote package
 */
export interface EncryptedVotePackage {
  commitHash: Uint8Array;
  encryptedData: Uint8Array;
  nonce: Uint8Array;
}
