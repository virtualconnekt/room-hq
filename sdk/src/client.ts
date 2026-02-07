/**
 * Main AptosRoom Client
 * Aggregates all module clients for easy access
 */
import {
  Aptos,
  AptosConfig,
  Network,
  Account,
  Ed25519PrivateKey,
  type PendingTransactionResponse,
  type UserTransactionResponse,
} from '@aptos-labs/ts-sdk';
import { KeycardClient } from './modules/keycard.js';
import { JurorRegistryClient } from './modules/registry.js';
import { RoomClient } from './modules/room.js';
import { JuryClient } from './modules/jury.js';
import { SettlementClient } from './modules/settlement.js';
import { CONSTANTS } from './constants.js';

/**
 * Configuration options for AptosRoom client
 */
export interface AptosRoomConfig {
  /** Aptos network to use */
  network?: Network;
  /** Custom module address (defaults to deployed address) */
  moduleAddress?: string;
  /** Custom Aptos config */
  aptosConfig?: AptosConfig;
}

/**
 * Main client for interacting with AptosRoom Protocol
 * 
 * @example
 * ```typescript
 * const client = new AptosRoomClient({ network: Network.TESTNET });
 * 
 * // Access module clients
 * await client.keycard.mint(account);
 * await client.room.create(account, params);
 * await client.jury.commitTierVote(account, roomId, tierA, tierB);
 * ```
 */
export class AptosRoomClient {
  public readonly aptos: Aptos;
  public readonly moduleAddress: string;

  // Module clients
  public readonly keycard: KeycardClient;
  public readonly registry: JurorRegistryClient;
  public readonly room: RoomClient;
  public readonly jury: JuryClient;
  public readonly settlement: SettlementClient;

  constructor(config: AptosRoomConfig = {}) {
    const aptosConfig = config.aptosConfig ?? new AptosConfig({
      network: config.network ?? Network.TESTNET,
    });

    this.aptos = new Aptos(aptosConfig);
    this.moduleAddress = config.moduleAddress ?? CONSTANTS.MODULE_ADDRESS;

    // Initialize module clients
    this.keycard = new KeycardClient(this.aptos, this.moduleAddress);
    this.registry = new JurorRegistryClient(this.aptos, this.moduleAddress);
    this.room = new RoomClient(this.aptos, this.moduleAddress);
    this.jury = new JuryClient(this.aptos, this.moduleAddress);
    this.settlement = new SettlementClient(this.aptos, this.moduleAddress);
  }

  /**
   * Create an account from a private key hex string
   */
  static accountFromPrivateKey(privateKeyHex: string): Account {
    const privateKey = new Ed25519PrivateKey(privateKeyHex);
    return Account.fromPrivateKey({ privateKey });
  }

  /**
   * Create a random account (for testing)
   */
  static generateAccount(): Account {
    return Account.generate();
  }

  /**
   * Wait for transaction and return result
   */
  async waitForTransaction(
    pendingTx: PendingTransactionResponse
  ): Promise<UserTransactionResponse> {
    return await this.aptos.waitForTransaction({
      transactionHash: pendingTx.hash,
    }) as UserTransactionResponse;
  }

  /**
   * Fund an account from faucet (testnet only)
   */
  async fundAccount(address: string, amount: number = 100_000_000): Promise<void> {
    await this.aptos.fundAccount({
      accountAddress: address,
      amount,
    });
  }

  /**
   * Get account balance
   */
  async getBalance(address: string): Promise<bigint> {
    const resources = await this.aptos.getAccountResource({
      accountAddress: address,
      resourceType: '0x1::coin::CoinStore<0x1::aptos_coin::AptosCoin>',
    });
    return BigInt((resources as { coin: { value: string } }).coin.value);
  }
}
