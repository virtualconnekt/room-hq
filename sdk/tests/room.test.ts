/**
 * Room Module Tests
 * Tests for room creation, submissions, and state management
 */
import {
  describe,
  it,
  expect,
  beforeAll,
  createTestClient,
  generateTestAccount,
  generateRandomHash,
  fundAccount,
  executeAndWait,
  futureTimestamp,
  AptosRoomClient,
  Account,
} from './setup.js';
import { STATES } from '../src/constants.js';

describe('Room Module', () => {
  let client: AptosRoomClient;
  let clientAccount: Account; // Room creator
  let contributorAccount: Account;
  let roomId: number;
  const testCategory = 'development';

  beforeAll(async () => {
    client = createTestClient();
    clientAccount = generateTestAccount();
    contributorAccount = generateTestAccount();

    // Fund accounts
    await fundAccount(client, clientAccount.accountAddress.toString());
    await fundAccount(client, contributorAccount.accountAddress.toString());

    // Mint keycards
    const mintTx1 = await client.keycard.mint(clientAccount);
    await executeAndWait(client, mintTx1);

    const mintTx2 = await client.keycard.mint(contributorAccount);
    await executeAndWait(client, mintTx2);
  }, 120000);

  describe('createRoom()', () => {
    it('should create a new room', async () => {
      const taskHash = generateRandomHash();
      const taskReward = 10_000_000n; // 0.1 APT

      const tx = await client.room.createRoom(clientAccount, {
        category: testCategory,
        taskHash,
        taskReward,
        submitDeadline: futureTimestamp(3600), // 1 hour
        commitDeadline: futureTimestamp(7200), // 2 hours
        revealDeadline: futureTimestamp(10800), // 3 hours
      });
      await executeAndWait(client, tx);

      // Room ID is 1 for first room
      roomId = 1;

      // Verify room was created
      const state = await client.room.getState(roomId);
      expect(state).toBe(STATES.INIT);

      const roomClient = await client.room.getClient(roomId);
      expect(roomClient.toLowerCase()).toBe(
        clientAccount.accountAddress.toString().toLowerCase()
      );
    }, 60000);
  });

  describe('openRoom()', () => {
    it('should open room for submissions', async () => {
      const tx = await client.room.openRoom(clientAccount, roomId);
      await executeAndWait(client, tx);

      const state = await client.room.getState(roomId);
      expect(state).toBe(STATES.OPEN);
    }, 30000);

    it('should fail if non-client tries to open', async () => {
      // Create another room first
      const taskHash = generateRandomHash();
      const createTx = await client.room.createRoom(clientAccount, {
        category: testCategory,
        taskHash,
        taskReward: 10_000_000n,
        submitDeadline: futureTimestamp(3600),
        commitDeadline: futureTimestamp(7200),
        revealDeadline: futureTimestamp(10800),
      });
      await executeAndWait(client, createTx);
      
      const newRoomId = 2;
      
      // Try to open with wrong account
      await expect(
        client.room.openRoom(contributorAccount, newRoomId)
      ).rejects.toThrow();
    }, 60000);
  });

  describe('submitEntry()', () => {
    it('should allow contributor to submit entry', async () => {
      const dataHash = generateRandomHash();

      const tx = await client.room.submitEntry(contributorAccount, roomId, dataHash);
      await executeAndWait(client, tx);

      // Verify contributor was added
      const isContributor = await client.room.isContributor(
        roomId,
        contributorAccount.accountAddress.toString()
      );
      expect(isContributor).toBe(true);

      const count = await client.room.getContributorCount(roomId);
      expect(count).toBeGreaterThanOrEqual(1);
    }, 30000);

    it('should fail if same contributor submits twice', async () => {
      const dataHash = generateRandomHash();
      await expect(
        client.room.submitEntry(contributorAccount, roomId, dataHash)
      ).rejects.toThrow();
    }, 30000);
  });

  describe('closeRoom()', () => {
    it('should close room for submissions', async () => {
      const tx = await client.room.closeRoom(clientAccount, roomId);
      await executeAndWait(client, tx);

      const state = await client.room.getState(roomId);
      expect(state).toBe(STATES.CLOSED);
    }, 30000);
  });

  describe('setClientScore()', () => {
    it('should set client score for contributor', async () => {
      const score = 85;
      const tx = await client.room.setClientScore(
        clientAccount,
        roomId,
        contributorAccount.accountAddress.toString(),
        score
      );
      await executeAndWait(client, tx);
      
      // Score is set (we can verify via final score after finalization)
    }, 30000);
  });

  describe('View Functions', () => {
    it('should return contributor list', async () => {
      const contributors = await client.room.getContributorList(roomId);
      expect(contributors.length).toBeGreaterThanOrEqual(1);
    });

    it('should return task reward', async () => {
      const reward = await client.room.getTaskReward(roomId);
      expect(reward).toBe(10_000_000n);
    });
  });
});
