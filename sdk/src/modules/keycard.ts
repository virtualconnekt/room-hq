/**
 * Keycard Module Client
 * Handles keycard NFT minting and queries
 */
import {
  Aptos,
  Account,
  type PendingTransactionResponse,
  type InputGenerateTransactionPayloadData,
} from '@aptos-labs/ts-sdk';
import type { Keycard } from '../types/index.js';

export class KeycardClient {
  constructor(
    private readonly aptos: Aptos,
    private readonly moduleAddress: string
  ) {}

  // ============================================================
  // ENTRY FUNCTIONS
  // ============================================================

  /**
   * Mint a new keycard for the account
   * Keycards are soulbound (non-transferrable)
   */
  async mint(account: Account): Promise<PendingTransactionResponse> {
    const payload: InputGenerateTransactionPayloadData = {
      function: `${this.moduleAddress}::keycard::mint`,
      functionArguments: [],
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
  // VIEW FUNCTIONS
  // ============================================================

  /**
   * Check if an address has a keycard
   */
  async hasKeycard(address: string): Promise<boolean> {
    const result = await this.aptos.view({
      payload: {
        function: `${this.moduleAddress}::keycard::has_keycard`,
        functionArguments: [address],
      },
    });
    return result[0] as boolean;
  }

  /**
   * Get keycard ID for an address
   */
  async getKeycardId(address: string): Promise<bigint> {
    const result = await this.aptos.view({
      payload: {
        function: `${this.moduleAddress}::keycard::get_keycard_id`,
        functionArguments: [address],
      },
    });
    return BigInt(result[0] as string);
  }

  /**
   * Get tasks completed count
   */
  async getTasksCompleted(address: string): Promise<number> {
    const result = await this.aptos.view({
      payload: {
        function: `${this.moduleAddress}::keycard::get_tasks_completed`,
        functionArguments: [address],
      },
    });
    return Number(result[0]);
  }

  /**
   * Get jury participations count
   */
  async getJuryParticipations(address: string): Promise<number> {
    const result = await this.aptos.view({
      payload: {
        function: `${this.moduleAddress}::keycard::get_jury_participations`,
        functionArguments: [address],
      },
    });
    return Number(result[0]);
  }

  /**
   * Get variance flags count
   */
  async getVarianceFlags(address: string): Promise<number> {
    const result = await this.aptos.view({
      payload: {
        function: `${this.moduleAddress}::keycard::get_variance_flags`,
        functionArguments: [address],
      },
    });
    return Number(result[0]);
  }

  /**
   * Get average score
   */
  async getAverageScore(address: string): Promise<number> {
    const result = await this.aptos.view({
      payload: {
        function: `${this.moduleAddress}::keycard::get_avg_score`,
        functionArguments: [address],
      },
    });
    return Number(result[0]);
  }

  /**
   * Get all keycard data
   */
  async getKeycard(address: string): Promise<Keycard> {
    const [hasCard, id, tasks, avgScore, jury, variance] = await Promise.all([
      this.hasKeycard(address),
      this.getKeycardId(address).catch(() => 0n),
      this.getTasksCompleted(address).catch(() => 0),
      this.getAverageScore(address).catch(() => 0),
      this.getJuryParticipations(address).catch(() => 0),
      this.getVarianceFlags(address).catch(() => 0),
    ]);

    if (!hasCard) {
      throw new Error('Keycard not found');
    }

    return {
      owner: address,
      tokenId: id.toString(),
      mintedAt: 0n, // Not exposed via view
    };
  }
}
