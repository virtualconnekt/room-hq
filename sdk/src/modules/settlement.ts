/**
 * Settlement Module Client
 * Handles settlement approval and execution
 */
import {
  Aptos,
  Account,
  type PendingTransactionResponse,
  type InputGenerateTransactionPayloadData,
} from '@aptos-labs/ts-sdk';

export class SettlementClient {
  constructor(
    private readonly aptos: Aptos,
    private readonly moduleAddress: string
  ) {}

  // ============================================================
  // ENTRY FUNCTIONS
  // ============================================================

  /**
   * Approve settlement (client or contributor)
   */
  async approveSettlement(
    account: Account,
    roomId: number
  ): Promise<PendingTransactionResponse> {
    const payload: InputGenerateTransactionPayloadData = {
      function: `${this.moduleAddress}::settlement::approve_settlement`,
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
   * Execute standard settlement (score-based)
   */
  async executeSettlement(
    account: Account,
    roomId: number
  ): Promise<PendingTransactionResponse> {
    const payload: InputGenerateTransactionPayloadData = {
      function: `${this.moduleAddress}::settlement::execute_settlement`,
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
   * Execute tier settlement (tier-based distribution)
   */
  async executeTierSettlement(
    account: Account,
    roomId: number
  ): Promise<PendingTransactionResponse> {
    const payload: InputGenerateTransactionPayloadData = {
      function: `${this.moduleAddress}::settlement::execute_tier_settlement`,
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

  // ============================================================
  // VIEW FUNCTIONS
  // ============================================================

  /**
   * Check if client has approved settlement
   */
  async hasClientApproved(roomId: number): Promise<boolean> {
    const result = await this.aptos.view({
      payload: {
        function: `${this.moduleAddress}::settlement::has_client_approved`,
        functionArguments: [BigInt(roomId)],
      },
    });
    return result[0] as boolean;
  }

  /**
   * Check if contributor has approved settlement
   */
  async hasContributorApproved(roomId: number, contributor: string): Promise<boolean> {
    const result = await this.aptos.view({
      payload: {
        function: `${this.moduleAddress}::settlement::has_contributor_approved`,
        functionArguments: [BigInt(roomId), contributor],
      },
    });
    return result[0] as boolean;
  }

  /**
   * Get number of contributors who approved
   */
  async getContributorApprovalCount(roomId: number): Promise<number> {
    const result = await this.aptos.view({
      payload: {
        function: `${this.moduleAddress}::settlement::get_contributor_approval_count`,
        functionArguments: [BigInt(roomId)],
      },
    });
    return Number(result[0]);
  }

  /**
   * Check if settlement is ready (enough approvals)
   */
  async isSettlementReady(roomId: number): Promise<boolean> {
    const result = await this.aptos.view({
      payload: {
        function: `${this.moduleAddress}::settlement::is_settlement_ready`,
        functionArguments: [BigInt(roomId)],
      },
    });
    return result[0] as boolean;
  }

  /**
   * Check if room is settled
   */
  async isSettled(roomId: number): Promise<boolean> {
    const result = await this.aptos.view({
      payload: {
        function: `${this.moduleAddress}::settlement::is_settled`,
        functionArguments: [BigInt(roomId)],
      },
    });
    return result[0] as boolean;
  }

  /**
   * Get payout amount for contributor
   */
  async getContributorPayout(roomId: number, contributor: string): Promise<bigint> {
    const result = await this.aptos.view({
      payload: {
        function: `${this.moduleAddress}::settlement::get_contributor_payout`,
        functionArguments: [BigInt(roomId), contributor],
      },
    });
    return BigInt(result[0] as string);
  }

  /**
   * Get payout amount for juror
   */
  async getJurorPayout(roomId: number, juror: string): Promise<bigint> {
    const result = await this.aptos.view({
      payload: {
        function: `${this.moduleAddress}::settlement::get_juror_payout`,
        functionArguments: [BigInt(roomId), juror],
      },
    });
    return BigInt(result[0] as string);
  }

  /**
   * Check if contributor has claimed payout
   */
  async hasContributorClaimed(roomId: number, contributor: string): Promise<boolean> {
    const result = await this.aptos.view({
      payload: {
        function: `${this.moduleAddress}::settlement::has_contributor_claimed`,
        functionArguments: [BigInt(roomId), contributor],
      },
    });
    return result[0] as boolean;
  }

  /**
   * Check if juror has claimed payout
   */
  async hasJurorClaimed(roomId: number, juror: string): Promise<boolean> {
    const result = await this.aptos.view({
      payload: {
        function: `${this.moduleAddress}::settlement::has_juror_claimed`,
        functionArguments: [BigInt(roomId), juror],
      },
    });
    return result[0] as boolean;
  }
}
