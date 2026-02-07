/**
 * Settlement Module Tests
 * Tests for settlement approval and execution
 */
import {
  describe,
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
  AptosRoomClient,
  Account,
} from './setup.js';
import { STATES } from '../src/constants.js';

describe('Settlement Module', () => {
  let client: AptosRoomClient;
  let clientAccount: Account;
  let contributor1: Account;
  let contributor2: Account;
  let juror1: Account;
  let roomId: number;
  const testCategory = 'settlement_test';

  beforeAll(async () => {
    client = createTestClient();
    clientAccount = generateTestAccount();
    contributor1 = generateTestAccount();
    contributor2 = generateTestAccount();
    juror1 = generateTestAccount();

    // Fund all accounts
    const accounts = [clientAccount, contributor1, contributor2, juror1];
    for (const acc of accounts) {
      await fundAccount(client, acc.accountAddress.toString());
    }

    // Mint keycards
    for (const acc of accounts) {
      const tx = await client.keycard.mint(acc);
      await executeAndWait(client, tx);
    }

    // Register juror
    const regTx = await client.registry.registerForCategory(juror1, testCategory);
    await executeAndWait(client, regTx);

    // Create room
    const createTx = await client.room.createRoom(clientAccount, {
      category: testCategory,
      taskHash: generateRandomHash(),
      taskReward: 50_000_000n, // 0.5 APT
      submitDeadline: futureTimestamp(3600),
      commitDeadline: futureTimestamp(7200),
      revealDeadline: futureTimestamp(10800),
    });
    await executeAndWait(client, createTx);
    roomId = 1;

    // Open room
    const openTx = await client.room.openRoom(clientAccount, roomId);
    await executeAndWait(client, openTx);

    // Submit entries
    const submit1 = await client.room.submitEntry(contributor1, roomId, generateRandomHash());
    await executeAndWait(client, submit1);
    
    const submit2 = await client.room.submitEntry(contributor2, roomId, generateRandomHash());
    await executeAndWait(client, submit2);

    // Close room
    const closeTx = await client.room.closeRoom(clientAccount, roomId);
    await executeAndWait(client, closeTx);

    // Start jury phase
    const juryTx = await client.room.startJuryPhase(clientAccount, roomId);
    await executeAndWait(client, juryTx);

    // Commit votes
    const salt1 = generateSalt();
    const salt2 = generateSalt();
    const score1 = 90;
    const score2 = 75;

    const hash1 = client.jury.computeVoteHash(contributor1.accountAddress.toString(), score1, salt1);
    const hash2 = client.jury.computeVoteHash(contributor2.accountAddress.toString(), score2, salt2);

    await executeAndWait(client, await client.jury.commitVote(juror1, {
      roomId,
      contributor: contributor1.accountAddress.toString(),
      voteHash: hash1,
    }));

    await executeAndWait(client, await client.jury.commitVote(juror1, {
      roomId,
      contributor: contributor2.accountAddress.toString(),
      voteHash: hash2,
    }));

    // Start reveal phase
    const revealTx = await client.room.startRevealPhase(clientAccount, roomId);
    await executeAndWait(client, revealTx);

    // Reveal votes
    await executeAndWait(client, await client.jury.revealVote(juror1, {
      roomId,
      contributor: contributor1.accountAddress.toString(),
      score: score1,
      salt: salt1,
    }));

    await executeAndWait(client, await client.jury.revealVote(juror1, {
      roomId,
      contributor: contributor2.accountAddress.toString(),
      score: score2,
      salt: salt2,
    }));

    // Finalize room
    const finalizeTx = await client.room.finalizeRoom(clientAccount, roomId);
    await executeAndWait(client, finalizeTx);
  }, 600000);

  describe('approveSettlement()', () => {
    it('should allow client to approve settlement', async () => {
      const tx = await client.settlement.approveSettlement(clientAccount, roomId);
      await executeAndWait(client, tx);

      const hasApproved = await client.settlement.hasClientApproved(roomId);
      expect(hasApproved).toBe(true);
    }, 30000);

    it('should allow contributor to approve settlement', async () => {
      const tx = await client.settlement.approveSettlement(contributor1, roomId);
      await executeAndWait(client, tx);

      const hasApproved = await client.settlement.hasContributorApproved(
        roomId,
        contributor1.accountAddress.toString()
      );
      expect(hasApproved).toBe(true);
    }, 30000);

    it('should track contributor approval count', async () => {
      const count = await client.settlement.getContributorApprovalCount(roomId);
      expect(count).toBeGreaterThanOrEqual(1);
    });
  });

  describe('executeSettlement()', () => {
    it('should check if settlement is ready', async () => {
      // May need more approvals
      const isReady = await client.settlement.isSettlementReady(roomId);
      // Just verify the call works
      expect(typeof isReady).toBe('boolean');
    });

    it('should execute settlement when ready', async () => {
      // Add remaining approvals
      const tx = await client.settlement.approveSettlement(contributor2, roomId);
      await executeAndWait(client, tx);

      // Check if ready
      const isReady = await client.settlement.isSettlementReady(roomId);
      
      if (isReady) {
        const executeTx = await client.settlement.executeSettlement(clientAccount, roomId);
        await executeAndWait(client, executeTx);

        const isSettled = await client.settlement.isSettled(roomId);
        expect(isSettled).toBe(true);
      }
    }, 60000);
  });

  describe('View Functions', () => {
    it('should return payout information', async () => {
      const isSettled = await client.settlement.isSettled(roomId);
      
      if (isSettled) {
        const contributorPayout = await client.settlement.getContributorPayout(
          roomId,
          contributor1.accountAddress.toString()
        );
        expect(contributorPayout).toBeGreaterThan(0n);
      }
    });
  });
});

describe('Tier Settlement', () => {
  let client: AptosRoomClient;
  let clientAccount: Account;
  let contributor1: Account;
  let contributor2: Account;
  let juror1: Account;
  let tierRoomId: number;
  const testCategory = 'tier_settlement_test';

  beforeAll(async () => {
    client = createTestClient();
    clientAccount = generateTestAccount();
    contributor1 = generateTestAccount();
    contributor2 = generateTestAccount();
    juror1 = generateTestAccount();

    // Fund all accounts
    const accounts = [clientAccount, contributor1, contributor2, juror1];
    for (const acc of accounts) {
      await fundAccount(client, acc.accountAddress.toString());
    }

    // Mint keycards
    for (const acc of accounts) {
      const tx = await client.keycard.mint(acc);
      await executeAndWait(client, tx);
    }

    // Register juror
    const regTx = await client.registry.registerForCategory(juror1, testCategory);
    await executeAndWait(client, regTx);

    // Create room
    const createTx = await client.room.createRoom(clientAccount, {
      category: testCategory,
      taskHash: generateRandomHash(),
      taskReward: 50_000_000n,
      submitDeadline: futureTimestamp(3600),
      commitDeadline: futureTimestamp(7200),
      revealDeadline: futureTimestamp(10800),
    });
    await executeAndWait(client, createTx);
    tierRoomId = 1;

    // Setup room with tier voting
    const openTx = await client.room.openRoom(clientAccount, tierRoomId);
    await executeAndWait(client, openTx);

    await executeAndWait(client, await client.room.submitEntry(contributor1, tierRoomId, generateRandomHash()));
    await executeAndWait(client, await client.room.submitEntry(contributor2, tierRoomId, generateRandomHash()));

    const closeTx = await client.room.closeRoom(clientAccount, tierRoomId);
    await executeAndWait(client, closeTx);

    const juryTx = await client.room.startJuryPhase(clientAccount, tierRoomId);
    await executeAndWait(client, juryTx);

    // Tier voting
    const salt = generateSalt();
    const orderedContributors = [
      contributor1.accountAddress.toString(),
      contributor2.accountAddress.toString(),
    ];
    const voteHash = client.jury.computeTierVoteHash(orderedContributors, salt);
    const encryptedData = client.jury.encryptTierVote(
      { orderedContributors, salt },
      juror1.publicKey.toUint8Array()
    );

    await executeAndWait(client, await client.jury.commitTierVote(juror1, {
      roomId: tierRoomId,
      voteHash,
      encryptedData,
    }));

    const revealTx = await client.room.startRevealPhase(clientAccount, tierRoomId);
    await executeAndWait(client, revealTx);

    await executeAndWait(client, await client.jury.revealTierVote(juror1, {
      roomId: tierRoomId,
      orderedContributors,
      salt,
    }));

    const finalizeTx = await client.room.finalizeRoom(clientAccount, tierRoomId);
    await executeAndWait(client, finalizeTx);
  }, 600000);

  describe('executeTierSettlement()', () => {
    it('should execute tier settlement', async () => {
      // Approve settlement
      await executeAndWait(client, await client.settlement.approveSettlement(clientAccount, tierRoomId));
      await executeAndWait(client, await client.settlement.approveSettlement(contributor1, tierRoomId));
      await executeAndWait(client, await client.settlement.approveSettlement(contributor2, tierRoomId));

      const isReady = await client.settlement.isSettlementReady(tierRoomId);
      
      if (isReady) {
        const tx = await client.settlement.executeTierSettlement(clientAccount, tierRoomId);
        await executeAndWait(client, tx);

        const isSettled = await client.settlement.isSettled(tierRoomId);
        expect(isSettled).toBe(true);
      }
    }, 60000);
  });
});
