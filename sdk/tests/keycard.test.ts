/**
 * Keycard Module Tests
 * Tests for keycard minting and view functions
 */
import {
  describeNetwork,
  it,
  expect,
  beforeAll,
  createTestClient,
  generateTestAccount,
  fundAccount,
  executeAndWait,
  AptosRoomClient,
  Account,
} from './setup.js';

describeNetwork('Keycard Module', () => {
  let client: AptosRoomClient;
  let testAccount: Account;

  beforeAll(async () => {
    client = createTestClient();
    testAccount = generateTestAccount();
    await fundAccount(client, testAccount.accountAddress.toString());
  }, 60000);

  describe('mint()', () => {
    it('should mint a keycard for a new account', async () => {
      // Verify account doesn't have keycard initially
      const hasKeycardBefore = await client.keycard.hasKeycard(
        testAccount.accountAddress.toString()
      );
      expect(hasKeycardBefore).toBe(false);

      // Mint keycard
      const tx = await client.keycard.mint(testAccount);
      await executeAndWait(client, tx);

      // Verify keycard was minted
      const hasKeycardAfter = await client.keycard.hasKeycard(
        testAccount.accountAddress.toString()
      );
      expect(hasKeycardAfter).toBe(true);
    }, 30000);

    it('should fail to mint a second keycard for same account', async () => {
      // Account already has keycard from previous test
      await expect(client.keycard.mint(testAccount)).rejects.toThrow();
    }, 30000);
  });

  describe('View Functions', () => {
    it('should return keycard ID', async () => {
      const keycardId = await client.keycard.getKeycardId(
        testAccount.accountAddress.toString()
      );
      expect(keycardId).toBeGreaterThanOrEqual(1);
    });

    it('should return initial stats as zero', async () => {
      const tasksCompleted = await client.keycard.getTasksCompleted(
        testAccount.accountAddress.toString()
      );
      expect(tasksCompleted).toBe(0);

      const juryParticipations = await client.keycard.getJuryParticipations(
        testAccount.accountAddress.toString()
      );
      expect(juryParticipations).toBe(0);

      const varianceFlags = await client.keycard.getVarianceFlags(
        testAccount.accountAddress.toString()
      );
      expect(varianceFlags).toBe(0);
    });
  });
});
