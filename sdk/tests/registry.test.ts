/**
 * Juror Registry Module Tests
 * Tests for juror registration and category management
 */
import {
  describe,
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

describe('Juror Registry Module', () => {
  let client: AptosRoomClient;
  let testAccount: Account;
  const testCategory = 'development';

  beforeAll(async () => {
    client = createTestClient();
    testAccount = generateTestAccount();
    await fundAccount(client, testAccount.accountAddress.toString());
    
    // Mint keycard first (required for registration)
    const mintTx = await client.keycard.mint(testAccount);
    await executeAndWait(client, mintTx);
  }, 60000);

  describe('registerForCategory()', () => {
    it('should register juror for a category', async () => {
      // Verify not registered initially
      const isRegisteredBefore = await client.registry.isRegistered(
        testAccount.accountAddress.toString(),
        testCategory
      );
      expect(isRegisteredBefore).toBe(false);

      // Register
      const tx = await client.registry.registerForCategory(testAccount, testCategory);
      await executeAndWait(client, tx);

      // Verify registration
      const isRegisteredAfter = await client.registry.isRegistered(
        testAccount.accountAddress.toString(),
        testCategory
      );
      expect(isRegisteredAfter).toBe(true);
    }, 30000);

    it('should register juror for multiple categories', async () => {
      const anotherCategory = 'design';
      
      const tx = await client.registry.registerForCategory(testAccount, anotherCategory);
      await executeAndWait(client, tx);

      // Get all registered categories
      const categories = await client.registry.getRegisteredCategories(
        testAccount.accountAddress.toString()
      );
      expect(categories).toContain(testCategory);
      expect(categories).toContain(anotherCategory);
    }, 30000);

    it('should fail to register for same category twice', async () => {
      await expect(
        client.registry.registerForCategory(testAccount, testCategory)
      ).rejects.toThrow();
    }, 30000);
  });

  describe('unregisterFromCategory()', () => {
    it('should unregister juror from a category', async () => {
      const categoryToRemove = 'design';
      
      // Verify registered
      const isRegisteredBefore = await client.registry.isRegistered(
        testAccount.accountAddress.toString(),
        categoryToRemove
      );
      expect(isRegisteredBefore).toBe(true);

      // Unregister
      const tx = await client.registry.unregisterFromCategory(testAccount, categoryToRemove);
      await executeAndWait(client, tx);

      // Verify unregistered
      const isRegisteredAfter = await client.registry.isRegistered(
        testAccount.accountAddress.toString(),
        categoryToRemove
      );
      expect(isRegisteredAfter).toBe(false);
    }, 30000);

    it('should fail to unregister from category not registered in', async () => {
      await expect(
        client.registry.unregisterFromCategory(testAccount, 'unknown_category')
      ).rejects.toThrow();
    }, 30000);
  });

  describe('View Functions', () => {
    it('should return jurors for a category', async () => {
      const jurors = await client.registry.getJurorsForCategory(testCategory);
      expect(jurors).toContain(testAccount.accountAddress.toString());
    });
  });
});
