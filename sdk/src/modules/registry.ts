/**
 * Juror Registry Module Client
 * Handles juror registration and category management
 */
import {
  Aptos,
  Account,
  type PendingTransactionResponse,
  type InputGenerateTransactionPayloadData,
} from '@aptos-labs/ts-sdk';

export class JurorRegistryClient {
  constructor(
    private readonly aptos: Aptos,
    private readonly moduleAddress: string
  ) {}

  // ============================================================
  // ENTRY FUNCTIONS
  // ============================================================

  /**
   * Register caller as juror for a category
   * Requires: caller has a keycard
   */
  async registerForCategory(
    account: Account,
    category: string
  ): Promise<PendingTransactionResponse> {
    const payload: InputGenerateTransactionPayloadData = {
      function: `${this.moduleAddress}::juror_registry::register_for_category`,
      functionArguments: [category],
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
   * Unregister caller from a category
   */
  async unregisterFromCategory(
    account: Account,
    category: string
  ): Promise<PendingTransactionResponse> {
    const payload: InputGenerateTransactionPayloadData = {
      function: `${this.moduleAddress}::juror_registry::unregister_from_category`,
      functionArguments: [category],
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
   * Check if address is registered as juror for a category
   */
  async isRegistered(jurorAddress: string, category: string): Promise<boolean> {
    const result = await this.aptos.view({
      payload: {
        function: `${this.moduleAddress}::juror_registry::is_registered`,
        functionArguments: [jurorAddress, category],
      },
    });
    return result[0] as boolean;
  }

  /**
   * Get all registered categories for a juror
   */
  async getRegisteredCategories(jurorAddress: string): Promise<string[]> {
    const result = await this.aptos.view({
      payload: {
        function: `${this.moduleAddress}::juror_registry::get_registered_categories`,
        functionArguments: [jurorAddress],
      },
    });
    return result[0] as string[];
  }

  /**
   * Get all jurors registered for a category
   */
  async getJurorsForCategory(category: string): Promise<string[]> {
    const result = await this.aptos.view({
      payload: {
        function: `${this.moduleAddress}::juror_registry::get_jurors_for_category`,
        functionArguments: [category],
      },
    });
    return result[0] as string[];
  }
}
