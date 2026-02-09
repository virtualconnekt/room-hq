/**
 * Jury Module Tests
 * Tests for commit-reveal voting (standard and tier)
 */
import {
  describe,
  describeNetwork,
  it,
  expect,
  beforeAll,
  createTestClient,
  generateTestAccount,
  generateRandomHash,
  generateSalt,
  fundAccount,
  executeAndWait,
  futureTimestamp,
  sleep,
  AptosRoomClient,
  Account,
  HashUtils,
  EncryptionUtils,
} from './setup.js';
import { STATES } from '../src/constants.js';

describeNetwork('Jury Module', () => {
  let client: AptosRoomClient;
  let clientAccount: Account;
  let contributor1: Account;
  let contributor2: Account;
  let juror1: Account;
  let juror2: Account;
  let roomId: number;
  const testCategory = 'jury_test';

  beforeAll(async () => {
    client = createTestClient();
    clientAccount = generateTestAccount();
    contributor1 = generateTestAccount();
    contributor2 = generateTestAccount();
    juror1 = generateTestAccount();
    juror2 = generateTestAccount();

    // Fund all accounts
    const accounts = [clientAccount, contributor1, contributor2, juror1, juror2];
    for (const acc of accounts) {
      await fundAccount(client, acc.accountAddress.toString());
    }

    // Mint keycards for all
    for (const acc of accounts) {
      const tx = await client.keycard.mint(acc);
      await executeAndWait(client, tx);
    }

    // Register jurors
    const regTx1 = await client.registry.registerForCategory(juror1, testCategory);
    await executeAndWait(client, regTx1);
    const regTx2 = await client.registry.registerForCategory(juror2, testCategory);
    await executeAndWait(client, regTx2);

    // Create a room
    const createTx = await client.room.createRoom(clientAccount, {
      category: testCategory,
      taskHash: generateRandomHash(),
      taskReward: 10_000_000n,
      submitDeadline: futureTimestamp(3600),
      commitDeadline: futureTimestamp(7200),
      revealDeadline: futureTimestamp(10800),
    });
    await executeAndWait(client, createTx);
    roomId = 1; // Use room from previous tests or track properly

    // Open room and add contributors
    const openTx = await client.room.openRoom(clientAccount, roomId);
    await executeAndWait(client, openTx);

    const submit1 = await client.room.submitEntry(contributor1, roomId, generateRandomHash());
    await executeAndWait(client, submit1);

    const submit2 = await client.room.submitEntry(contributor2, roomId, generateRandomHash());
    await executeAndWait(client, submit2);

    // Close room
    const closeTx = await client.room.closeRoom(clientAccount, roomId);
    await executeAndWait(client, closeTx);
  }, 300000);

  describe('Standard Voting (commitVote/revealVote)', () => {
    const salt1 = generateSalt();
    const score1 = 80;

    it('should start jury phase', async () => {
      const tx = await client.room.startJuryPhase(clientAccount, roomId);
      await executeAndWait(client, tx);

      const state = await client.room.getState(roomId);
      expect(state).toBe(STATES.JURY_ACTIVE);
    }, 30000);

    it('should commit a vote', async () => {
      const voteHash = client.jury.computeVoteHash(
        contributor1.accountAddress.toString(),
        score1,
        salt1
      );

      const tx = await client.jury.commitVote(juror1, {
        roomId,
        contributor: contributor1.accountAddress.toString(),
        voteHash,
      });
      await executeAndWait(client, tx);

      // Verify commit
      const hasCommitted = await client.jury.hasCommittedVote(
        roomId,
        juror1.accountAddress.toString(),
        contributor1.accountAddress.toString()
      );
      expect(hasCommitted).toBe(true);
    }, 30000);

    it('should start reveal phase', async () => {
      const tx = await client.room.startRevealPhase(clientAccount, roomId);
      await executeAndWait(client, tx);

      const state = await client.room.getState(roomId);
      expect(state).toBe(STATES.JURY_REVEAL);
    }, 30000);

    it('should reveal a vote', async () => {
      const tx = await client.jury.revealVote(juror1, {
        roomId,
        contributor: contributor1.accountAddress.toString(),
        score: score1,
        salt: salt1,
      });
      await executeAndWait(client, tx);

      // Verify reveal
      const hasRevealed = await client.jury.hasRevealedVote(
        roomId,
        juror1.accountAddress.toString(),
        contributor1.accountAddress.toString()
      );
      expect(hasRevealed).toBe(true);

      const revealedScore = await client.jury.getVoteScore(
        roomId,
        juror1.accountAddress.toString(),
        contributor1.accountAddress.toString()
      );
      expect(revealedScore).toBe(score1);
    }, 30000);

    it('should fail to reveal with wrong score', async () => {
      // Setup another vote first
      const salt = generateSalt();
      const correctScore = 75;
      const wrongScore = 90;

      const voteHash = client.jury.computeVoteHash(
        contributor2.accountAddress.toString(),
        correctScore,
        salt
      );

      // Commit with correct hash
      const commitTx = await client.jury.commitVote(juror1, {
        roomId,
        contributor: contributor2.accountAddress.toString(),
        voteHash,
      });
      await executeAndWait(client, commitTx);

      // Try to reveal with wrong score
      await expect(
        client.jury.revealVote(juror1, {
          roomId,
          contributor: contributor2.accountAddress.toString(),
          score: wrongScore,
          salt,
        })
      ).rejects.toThrow();
    }, 60000);
  });

  describe('Tier Voting (commitTierVote/revealTierVote)', () => {
    let tierRoomId: number;
    const salt = generateSalt();

    beforeAll(async () => {
      // Create a new room for tier voting
      const createTx = await client.room.createRoom(clientAccount, {
        category: testCategory,
        taskHash: generateRandomHash(),
        taskReward: 10_000_000n,
        submitDeadline: futureTimestamp(3600),
        commitDeadline: futureTimestamp(7200),
        revealDeadline: futureTimestamp(10800),
      });
      await executeAndWait(client, createTx);
      tierRoomId = 2; // Second room

      // Open and add contributors
      const openTx = await client.room.openRoom(clientAccount, tierRoomId);
      await executeAndWait(client, openTx);

      const submit1 = await client.room.submitEntry(contributor1, tierRoomId, generateRandomHash());
      await executeAndWait(client, submit1);

      const submit2 = await client.room.submitEntry(contributor2, tierRoomId, generateRandomHash());
      await executeAndWait(client, submit2);

      // Close room
      const closeTx = await client.room.closeRoom(clientAccount, tierRoomId);
      await executeAndWait(client, closeTx);

      // Start jury phase
      const juryTx = await client.room.startJuryPhase(clientAccount, tierRoomId);
      await executeAndWait(client, juryTx);
    }, 180000);

    it('should commit a tier vote with encrypted data', async () => {
      // Define tier selections (Tier A = 1 contributor for <10 contributors)
      const tierA = [contributor1.accountAddress.toString()];
      const tierB = [contributor2.accountAddress.toString()];

      const voteHash = client.jury.computeTierVoteHash(tierA, tierB, salt);

      // Encrypt vote data for on-chain storage
      const voteData = { tierA, tierB, salt };
      const encryptedData = client.jury.encryptTierVote(
        voteData,
        juror1.publicKey.toUint8Array()
      );

      const tx = await client.jury.commitTierVote(juror1, {
        roomId: tierRoomId,
        voteHash,
        encryptedData,
      });
      await executeAndWait(client, tx);

      // Verify commit
      const hasTierVote = await client.jury.hasTierVote(
        tierRoomId,
        juror1.accountAddress.toString()
      );
      expect(hasTierVote).toBe(true);

      const commitCount = await client.jury.getTierCommitCount(tierRoomId);
      expect(commitCount).toBeGreaterThanOrEqual(1);
    }, 30000);

    it('should retrieve encrypted data from chain', async () => {
      const encryptedData = await client.jury.getTierVoteEncrypted(
        tierRoomId,
        juror1.accountAddress.toString()
      );
      expect(encryptedData.length).toBeGreaterThan(0);
    });

    it('should reveal a tier vote', async () => {
      // Start reveal phase
      const revealPhaseTx = await client.room.startRevealPhase(clientAccount, tierRoomId);
      await executeAndWait(client, revealPhaseTx);

      // Use same tier selections as commit
      const tierA = [contributor1.accountAddress.toString()];
      const tierB = [contributor2.accountAddress.toString()];

      const tx = await client.jury.revealTierVote(juror1, {
        roomId: tierRoomId,
        tierA,
        tierB,
        salt,
      });
      await executeAndWait(client, tx);

      // Verify reveal
      const isRevealed = await client.jury.isTierVoteRevealed(
        tierRoomId,
        juror1.accountAddress.toString()
      );
      expect(isRevealed).toBe(true);

      const revealCount = await client.jury.getTierRevealCount(tierRoomId);
      expect(revealCount).toBeGreaterThanOrEqual(1);
    }, 60000);

    it('should get revealed tier selections', async () => {
      // Note: getTierVoteOrdering may need to be updated in SDK to match new return type
      const ordering = await client.jury.getTierVoteOrdering(
        tierRoomId,
        juror1.accountAddress.toString()
      );
      // The returned ordering should include tier A contributors
      expect(ordering).toContain(contributor1.accountAddress.toString());
    });
  });

  describe('Hash Utilities', () => {
    it('should produce consistent vote hashes', () => {
      const contributor = '0x1234567890abcdef';
      const score = 85;
      const salt = generateSalt();

      const hash1 = client.jury.computeVoteHash(contributor, score, salt);
      const hash2 = client.jury.computeVoteHash(contributor, score, salt);

      expect(hash1).toEqual(hash2);
    });

    it('should produce different hashes for different inputs', () => {
      const contributor = '0x1234567890abcdef';
      const salt = generateSalt();

      const hash1 = client.jury.computeVoteHash(contributor, 85, salt);
      const hash2 = client.jury.computeVoteHash(contributor, 90, salt);

      expect(hash1).not.toEqual(hash2);
    });
  });
});
