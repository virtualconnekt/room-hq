/**
 * Room Module Client
 * Handles room creation, submissions, state management
 */
import {
  Aptos,
  Account,
  type PendingTransactionResponse,
  type InputGenerateTransactionPayloadData,
} from '@aptos-labs/ts-sdk';
import type { Room } from '../types/index.js';

export interface CreateRoomParams {
  category: string;
  taskHash: Uint8Array;
  taskReward: bigint | number;
  submitDeadline: number;
  commitDeadline: number;
  revealDeadline: number;
}

export class RoomClient {
  constructor(
    private readonly aptos: Aptos,
    private readonly moduleAddress: string
  ) {}

  // ============================================================
  // ENTRY FUNCTIONS
  // ============================================================

  /**
   * Create a new room
   * Requires: caller has keycard, sufficient funds for escrow
   */
  async createRoom(
    account: Account,
    params: CreateRoomParams
  ): Promise<PendingTransactionResponse> {
    const payload: InputGenerateTransactionPayloadData = {
      function: `${this.moduleAddress}::room::create_room`,
      functionArguments: [
        params.category,
        Array.from(params.taskHash),
        BigInt(params.taskReward),
        BigInt(params.submitDeadline),
        BigInt(params.commitDeadline),
        BigInt(params.revealDeadline),
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
   * Open room for submissions (INIT -> OPEN)
   */
  async openRoom(
    account: Account,
    roomId: number
  ): Promise<PendingTransactionResponse> {
    const payload: InputGenerateTransactionPayloadData = {
      function: `${this.moduleAddress}::room::open_room`,
      functionArguments: [BigInt(roomId)],
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
   * Submit work entry to room
   */
  async submitEntry(
    account: Account,
    roomId: number,
    dataHash: Uint8Array
  ): Promise<PendingTransactionResponse> {
    const payload: InputGenerateTransactionPayloadData = {
      function: `${this.moduleAddress}::room::submit_entry`,
      functionArguments: [BigInt(roomId), Array.from(dataHash)],
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
   * Close room for submissions (OPEN -> CLOSED)
   */
  async closeRoom(
    account: Account,
    roomId: number
  ): Promise<PendingTransactionResponse> {
    const payload: InputGenerateTransactionPayloadData = {
      function: `${this.moduleAddress}::room::close_room`,
      functionArguments: [BigInt(roomId)],
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
   * Start jury phase (CLOSED -> JURY_ACTIVE)
   */
  async startJuryPhase(
    account: Account,
    roomId: number
  ): Promise<PendingTransactionResponse> {
    const payload: InputGenerateTransactionPayloadData = {
      function: `${this.moduleAddress}::room::start_jury_phase`,
      functionArguments: [BigInt(roomId)],
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
   * Start reveal phase (JURY_ACTIVE -> JURY_REVEAL)
   */
  async startRevealPhase(
    account: Account,
    roomId: number
  ): Promise<PendingTransactionResponse> {
    const payload: InputGenerateTransactionPayloadData = {
      function: `${this.moduleAddress}::room::start_reveal_phase`,
      functionArguments: [BigInt(roomId)],
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
   * Finalize room (JURY_REVEAL -> FINALIZED)
   */
  async finalizeRoom(
    account: Account,
    roomId: number
  ): Promise<PendingTransactionResponse> {
    const payload: InputGenerateTransactionPayloadData = {
      function: `${this.moduleAddress}::room::finalize_room`,
      functionArguments: [BigInt(roomId)],
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
   * Set client score for a contributor
   */
  async setClientScore(
    account: Account,
    roomId: number,
    contributor: string,
    score: number
  ): Promise<PendingTransactionResponse> {
    const payload: InputGenerateTransactionPayloadData = {
      function: `${this.moduleAddress}::room::set_client_score`,
      functionArguments: [BigInt(roomId), contributor, BigInt(score)],
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
   * Get room state
   */
  async getState(roomId: number): Promise<number> {
    const result = await this.aptos.view({
      payload: {
        function: `${this.moduleAddress}::room::get_state`,
        functionArguments: [BigInt(roomId)],
      },
    });
    return Number(result[0]);
  }

  /**
   * Get room client address
   */
  async getClient(roomId: number): Promise<string> {
    const result = await this.aptos.view({
      payload: {
        function: `${this.moduleAddress}::room::get_client`,
        functionArguments: [BigInt(roomId)],
      },
    });
    return result[0] as string;
  }

  /**
   * Get contributor count
   */
  async getContributorCount(roomId: number): Promise<number> {
    const result = await this.aptos.view({
      payload: {
        function: `${this.moduleAddress}::room::get_contributor_count`,
        functionArguments: [BigInt(roomId)],
      },
    });
    return Number(result[0]);
  }

  /**
   * Get contributors list
   */
  async getContributorList(roomId: number): Promise<string[]> {
    const result = await this.aptos.view({
      payload: {
        function: `${this.moduleAddress}::room::get_contributor_list`,
        functionArguments: [BigInt(roomId)],
      },
    });
    return result[0] as string[];
  }

  /**
   * Get jury pool
   */
  async getJuryPool(roomId: number): Promise<string[]> {
    const result = await this.aptos.view({
      payload: {
        function: `${this.moduleAddress}::room::get_jury_pool`,
        functionArguments: [BigInt(roomId)],
      },
    });
    return result[0] as string[];
  }

  /**
   * Check if address is a contributor
   */
  async isContributor(roomId: number, address: string): Promise<boolean> {
    const result = await this.aptos.view({
      payload: {
        function: `${this.moduleAddress}::room::is_contributor`,
        functionArguments: [BigInt(roomId), address],
      },
    });
    return result[0] as boolean;
  }

  /**
   * Check if address is a juror
   */
  async isJuror(roomId: number, address: string): Promise<boolean> {
    const result = await this.aptos.view({
      payload: {
        function: `${this.moduleAddress}::room::is_juror`,
        functionArguments: [BigInt(roomId), address],
      },
    });
    return result[0] as boolean;
  }

  /**
   * Get task reward amount
   */
  async getTaskReward(roomId: number): Promise<bigint> {
    const result = await this.aptos.view({
      payload: {
        function: `${this.moduleAddress}::room::get_task_reward`,
        functionArguments: [BigInt(roomId)],
      },
    });
    return BigInt(result[0] as string);
  }

  /**
   * Get final score for a contributor
   */
  async getFinalScore(roomId: number, contributor: string): Promise<number> {
    const result = await this.aptos.view({
      payload: {
        function: `${this.moduleAddress}::room::get_final_score`,
        functionArguments: [BigInt(roomId), contributor],
      },
    });
    return Number(result[0]);
  }

  /**
   * Get contributor tier
   */
  async getContributorTier(roomId: number, contributor: string): Promise<number> {
    const result = await this.aptos.view({
      payload: {
        function: `${this.moduleAddress}::room::get_contributor_tier`,
        functionArguments: [BigInt(roomId), contributor],
      },
    });
    return Number(result[0]);
  }

  /**
   * Check if tiers are computed
   */
  async areTiersComputed(roomId: number): Promise<boolean> {
    const result = await this.aptos.view({
      payload: {
        function: `${this.moduleAddress}::room::are_tiers_computed`,
        functionArguments: [BigInt(roomId)],
      },
    });
    return result[0] as boolean;
  }
}
