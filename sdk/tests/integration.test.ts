/**
 * Integration Tests
 * Full end-to-end workflow tests
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

describe('Full Workflow Integration', () => {
  let client: AptosRoomClient;
  
  // Participants
  let roomClient: Account;
  let contributor1: Account;
  let contributor2: Account;
  let contributor3: Account;
  let juror1: Account;
  let juror2: Account;
  let juror3: Account;
  
  const testCategory = 'integration_test';
  let roomId: number;

  beforeAll(async () => {
    client = createTestClient();
    
    // Generate all accounts
    roomClient = generateTestAccount();
    contributor1 = generateTestAccount();
    contributor2 = generateTestAccount();
    contributor3 = generateTestAccount();
    juror1 = generateTestAccount();
    juror2 = generateTestAccount();
    juror3 = generateTestAccount();

    // Fund all accounts
    const allAccounts = [
      roomClient, contributor1, contributor2, contributor3,
      juror1, juror2, juror3
    ];
    
    for (const acc of allAccounts) {
      await fundAccount(client, acc.accountAddress.toString());
    }
    
    // Mint keycards for all
    for (const acc of allAccounts) {
      const tx = await client.keycard.mint(acc);
      await executeAndWait(client, tx);
    }
  }, 300000);

  describe('Phase 1: Setup', () => {
    it('should register jurors for category', async () => {
      const jurors = [juror1, juror2, juror3];
      
      for (const juror of jurors) {
        const tx = await client.registry.registerForCategory(juror, testCategory);
        await executeAndWait(client, tx);
      }

      // Verify registrations
      for (const juror of jurors) {
        const isRegistered = await client.registry.isRegistered(
          juror.accountAddress.toString(),
          testCategory
        );
        expect(isRegistered).toBe(true);
      }
    }, 120000);
  });

  describe('Phase 2: Room Creation', () => {
    it('should create a room with task', async () => {
      const taskHash = generateRandomHash();
      const taskReward = 100_000_000n; // 1 APT

      const tx = await client.room.createRoom(roomClient, {
        category: testCategory,
        taskHash,
        taskReward,
        submitDeadline: futureTimestamp(3600),
        commitDeadline: futureTimestamp(7200),
        revealDeadline: futureTimestamp(10800),
      });
      await executeAndWait(client, tx);

      roomId = 1;

      const state = await client.room.getState(roomId);
      expect(state).toBe(STATES.INIT);
    }, 60000);

    it('should open room for submissions', async () => {
      const tx = await client.room.openRoom(roomClient, roomId);
      await executeAndWait(client, tx);

      const state = await client.room.getState(roomId);
      expect(state).toBe(STATES.OPEN);
    }, 30000);
  });

  describe('Phase 3: Submissions', () => {
    it('should accept submissions from contributors', async () => {
      const contributors = [contributor1, contributor2, contributor3];
      
      for (const contrib of contributors) {
        const dataHash = generateRandomHash();
        const tx = await client.room.submitEntry(contrib, roomId, dataHash);
        await executeAndWait(client, tx);
      }

      const count = await client.room.getContributorCount(roomId);
      expect(count).toBe(3);
    }, 120000);

    it('should close room for submissions', async () => {
      const tx = await client.room.closeRoom(roomClient, roomId);
      await executeAndWait(client, tx);

      const state = await client.room.getState(roomId);
      expect(state).toBe(STATES.CLOSED);
    }, 30000);
  });

  describe('Phase 4: Jury Voting (Tier-Based)', () => {
    const jurorSalts: Map<string, Uint8Array> = new Map();
    const orderedContributors: string[] = [];

    beforeAll(() => {
      // Define the ranking order (same for all jurors in this test)
      orderedContributors.push(
        contributor1.accountAddress.toString(),
        contributor2.accountAddress.toString(),
        contributor3.accountAddress.toString()
      );
    });

    it('should start jury phase', async () => {
      const tx = await client.room.startJuryPhase(roomClient, roomId);
      await executeAndWait(client, tx);

      const state = await client.room.getState(roomId);
      expect(state).toBe(STATES.JURY_ACTIVE);
    }, 30000);

    it('should accept tier vote commits from jurors', async () => {
      const jurors = [juror1, juror2, juror3];
      
      for (const juror of jurors) {
        const salt = generateSalt();
        jurorSalts.set(juror.accountAddress.toString(), salt);

        const voteHash = client.jury.computeTierVoteHash(orderedContributors, salt);
        const encryptedData = client.jury.encryptTierVote(
          { orderedContributors, salt },
          juror.publicKey.toUint8Array()
        );

        const tx = await client.jury.commitTierVote(juror, {
          roomId,
          voteHash,
          encryptedData,
        });
        await executeAndWait(client, tx);
      }

      const commitCount = await client.jury.getTierCommitCount(roomId);
      expect(commitCount).toBe(3);
    }, 120000);

    it('should start reveal phase', async () => {
      const tx = await client.room.startRevealPhase(roomClient, roomId);
      await executeAndWait(client, tx);

      const state = await client.room.getState(roomId);
      expect(state).toBe(STATES.JURY_REVEAL);
    }, 30000);

    it('should accept tier vote reveals from jurors', async () => {
      const jurors = [juror1, juror2, juror3];
      
      for (const juror of jurors) {
        const salt = jurorSalts.get(juror.accountAddress.toString())!;

        const tx = await client.jury.revealTierVote(juror, {
          roomId,
          orderedContributors,
          salt,
        });
        await executeAndWait(client, tx);
      }

      const revealCount = await client.jury.getTierRevealCount(roomId);
      expect(revealCount).toBe(3);
    }, 120000);
  });

  describe('Phase 5: Finalization', () => {
    it('should finalize room', async () => {
      const tx = await client.room.finalizeRoom(roomClient, roomId);
      await executeAndWait(client, tx);

      const state = await client.room.getState(roomId);
      expect(state).toBe(STATES.FINALIZED);
    }, 30000);

    it('should have computed tiers', async () => {
      const tiersComputed = await client.room.areTiersComputed(roomId);
      expect(tiersComputed).toBe(true);
    });

    it('should have assigned final scores', async () => {
      const score1 = await client.room.getFinalScore(
        roomId,
        contributor1.accountAddress.toString()
      );
      expect(score1).toBeGreaterThan(0);
    });
  });

  describe('Phase 6: Settlement', () => {
    it('should collect settlement approvals', async () => {
      // Client approves
      const clientTx = await client.settlement.approveSettlement(roomClient, roomId);
      await executeAndWait(client, clientTx);

      // Contributors approve
      const contributors = [contributor1, contributor2, contributor3];
      for (const contrib of contributors) {
        const tx = await client.settlement.approveSettlement(contrib, roomId);
        await executeAndWait(client, tx);
      }

      const isReady = await client.settlement.isSettlementReady(roomId);
      expect(isReady).toBe(true);
    }, 180000);

    it('should execute tier settlement', async () => {
      const tx = await client.settlement.executeTierSettlement(roomClient, roomId);
      await executeAndWait(client, tx);

      const isSettled = await client.settlement.isSettled(roomId);
      expect(isSettled).toBe(true);
    }, 60000);

    it('should have distributed payouts', async () => {
      const payout1 = await client.settlement.getContributorPayout(
        roomId,
        contributor1.accountAddress.toString()
      );
      expect(payout1).toBeGreaterThan(0n);

      // Top contributor should have highest payout
      const payout2 = await client.settlement.getContributorPayout(
        roomId,
        contributor2.accountAddress.toString()
      );
      const payout3 = await client.settlement.getContributorPayout(
        roomId,
        contributor3.accountAddress.toString()
      );

      // Based on tier ordering, contributor1 should have highest payout
      expect(payout1).toBeGreaterThanOrEqual(payout2);
      expect(payout2).toBeGreaterThanOrEqual(payout3);
    });
  });
});
