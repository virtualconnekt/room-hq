/**
 * Test Setup and Utilities
 * Shared test configuration and helper functions
 */
import { describe, it, expect, beforeAll, beforeEach } from 'vitest';
import { Account, Network } from '@aptos-labs/ts-sdk';
import { AptosRoomClient } from '../src/client.js';
import { HashUtils } from '../src/utils/hash.js';
import { EncryptionUtils } from '../src/utils/encryption.js';

// Test configuration
// Set APTOS_NETWORK=LOCAL to use local node, or provide pre-funded private keys
export const TEST_CONFIG = {
  network: (process.env.APTOS_NETWORK === 'LOCAL' ? Network.LOCAL : 
            process.env.APTOS_NETWORK === 'DEVNET' ? Network.DEVNET : Network.TESTNET),
  // Use the deployed contract address (devnet or testnet)
  moduleAddress: process.env.MODULE_ADDRESS || (
    process.env.APTOS_NETWORK === 'DEVNET' 
      ? '0x73b46b42953dbe67a69830d235355e30dc3e10b6f9a1101ce79f63c2b878de5b'
      : '0x2bf0af3ddc84bf1d6d32e0961a678cca4cd49f4f3a79b5b9d3b892bbfa6cc455'
  ),
  // Funding amount for test accounts (0.5 APT)
  fundingAmount: 50_000_000,
  // Timeout for transactions
  txTimeout: 30_000,
  // Skip network tests if faucet unavailable
  skipNetworkTests: process.env.SKIP_NETWORK_TESTS === 'true',
};

// Log test configuration
console.log(`Test Config: network=${TEST_CONFIG.network}, skipNetwork=${TEST_CONFIG.skipNetworkTests}`);

/**
 * Create a new test client
 */
export function createTestClient(): AptosRoomClient {
  return new AptosRoomClient({
    network: TEST_CONFIG.network,
    moduleAddress: TEST_CONFIG.moduleAddress,
  });
}

/**
 * Generate a new test account
 */
export function generateTestAccount(): Account {
  return Account.generate();
}

/**
 * Generate a random 32-byte hash (for task hashes, data hashes, etc.)
 */
export function generateRandomHash(): Uint8Array {
  const hash = new Uint8Array(32);
  crypto.getRandomValues(hash);
  return hash;
}

/**
 * Generate a random 32-byte salt
 */
export function generateSalt(): Uint8Array {
  return EncryptionUtils.generateSalt();
}

/**
 * Get current timestamp + offset in seconds
 */
export function futureTimestamp(offsetSeconds: number): number {
  return Math.floor(Date.now() / 1000) + offsetSeconds;
}

/**
 * Wait for a specified number of milliseconds
 */
export function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * Fund an account and wait for confirmation
 */
export async function fundAccount(
  client: AptosRoomClient,
  address: string,
  amount: number = TEST_CONFIG.fundingAmount
): Promise<void> {
  await client.fundAccount(address, amount);
  // Brief delay to ensure funds are available
  await sleep(1000);
}

/**
 * Execute transaction and wait for result
 */
export async function executeAndWait(
  client: AptosRoomClient,
  pendingTx: { hash: string }
): Promise<void> {
  await client.waitForTransaction(pendingTx as any);
}

// Export test utilities
export { describe, it, expect, beforeAll, beforeEach };
export { Account, Network };
export { AptosRoomClient };
export { HashUtils, EncryptionUtils };

/**
 * Conditionally skip network tests
 */
export const describeNetwork = TEST_CONFIG.skipNetworkTests 
  ? describe.skip 
  : describe;
