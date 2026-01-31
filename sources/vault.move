/// ============================================================
/// MODULE: Vault
/// SPEC: EXECUTION_TASKS_BY_PHASE.md Section 2.2
/// INVARIANTS ENFORCED:
///   - INVARIANT_ROOM_003: Escrow locked until Settled state
/// PURPOSE: Hold and release escrow funds for rooms
/// ============================================================
module aptosroom::vault {
    use std::signer;
    use aptos_std::table::{Self, Table};
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use aptosroom::errors;

    // Friend declarations
    friend aptosroom::room;
    friend aptosroom::settlement;
    friend aptosroom::aggregation;

    // ============================================================
    // STRUCTS
    // ============================================================

    /// Escrow vault for a single room
    struct Vault has store {
        /// Associated room ID
        room_id: u64,
        /// Locked funds
        balance: Coin<AptosCoin>,
        /// Lock state (INVARIANT_ROOM_003)
        locked: bool,
        /// Client who deposited
        client: address,
        /// Task reward amount
        task_reward: u64,
    }

    /// Capability for protocol to manage vaults
    struct VaultMutator has key {
        dummy: bool,
    }

    /// Registry of all vaults (maps room_id to Vault)
    struct VaultRegistry has key {
        /// Next vault ID
        next_id: u64,
        /// Vaults table: room_id -> Vault
        vaults: Table<u64, Vault>,
    }

    // ============================================================
    // EVENTS
    // ============================================================

    #[event]
    struct EscrowDeposited has drop, store {
        room_id: u64,
        depositor: address,
        amount: u64,
        timestamp: u64,
    }

    #[event]
    struct EscrowReleased has drop, store {
        room_id: u64,
        recipient: address,
        amount: u64,
        timestamp: u64,
    }

    #[event]
    struct VaultUnlocked has drop, store {
        room_id: u64,
        timestamp: u64,
    }

    // ============================================================
    // INITIALIZATION
    // ============================================================

    /// Initialize vault registry (called once at module publish)
    fun init_module(account: &signer) {
        move_to(account, VaultRegistry {
            next_id: 1,
            vaults: table::new<u64, Vault>(),
        });
        move_to(account, VaultMutator { dummy: true });
    }

    // ============================================================
    // PUBLIC FRIEND FUNCTIONS
    // ============================================================

    /// Create a new vault with escrow deposit
    /// Called by room module during room creation
    public(friend) fun create_vault(
        client: address,
        room_id: u64,
        deposit: Coin<AptosCoin>,
        task_reward: u64,
    ) acquires VaultRegistry {
        // Assert sufficient deposit
        assert!(
            coin::value(&deposit) >= task_reward,
            errors::E_INSUFFICIENT_ESCROW()
        );

        // Create vault
        let vault = Vault {
            room_id,
            balance: deposit,
            locked: true,
            client,
            task_reward,
        };

        // Store in registry
        let registry = borrow_global_mut<VaultRegistry>(@aptosroom);
        table::add(&mut registry.vaults, room_id, vault);

        // Emit event
        event::emit(EscrowDeposited {
            room_id,
            depositor: client,
            amount: task_reward,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Get vault balance
    public fun get_balance(room_id: u64): u64 acquires VaultRegistry {
        let registry = borrow_global<VaultRegistry>(@aptosroom);
        let vault = table::borrow(&registry.vaults, room_id);
        coin::value(&vault.balance)
    }

    /// Check if vault is locked
    public fun is_locked(room_id: u64): bool acquires VaultRegistry {
        let registry = borrow_global<VaultRegistry>(@aptosroom);
        let vault = table::borrow(&registry.vaults, room_id);
        vault.locked
    }

    /// Unlock vault (called when room reaches SETTLED state)
    public(friend) fun unlock_vault(room_id: u64) acquires VaultRegistry {
        let registry = borrow_global_mut<VaultRegistry>(@aptosroom);
        let vault = table::borrow_mut(&mut registry.vaults, room_id);
        vault.locked = false;

        // Emit event
        event::emit(VaultUnlocked {
            room_id,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Release funds to winner
    /// INVARIANT_ROOM_003: Only callable when vault is unlocked
    public(friend) fun release_to_winner(
        room_id: u64,
        winner: address,
        amount: u64,
    ) acquires VaultRegistry {
        let registry = borrow_global_mut<VaultRegistry>(@aptosroom);
        let vault = table::borrow_mut(&mut registry.vaults, room_id);

        // Assert vault is unlocked
        assert!(!vault.locked, errors::E_VAULT_LOCKED());

        // Assert sufficient balance
        assert!(
            coin::value(&vault.balance) >= amount,
            errors::E_INSUFFICIENT_BALANCE()
        );

        // Extract coins and deposit to winner
        let payout = coin::extract(&mut vault.balance, amount);
        coin::deposit(winner, payout);

        // Emit event
        event::emit(EscrowReleased {
            room_id,
            recipient: winner,
            amount,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Refund escrow to client (zero votes case)
    public(friend) fun refund_to_client(room_id: u64) acquires VaultRegistry {
        let registry = borrow_global_mut<VaultRegistry>(@aptosroom);
        let vault = table::borrow_mut(&mut registry.vaults, room_id);

        let client = vault.client;
        let amount = coin::value(&vault.balance);

        // Extract all coins and deposit to client
        let refund = coin::extract_all(&mut vault.balance);
        coin::deposit(client, refund);

        // Unlock vault
        vault.locked = false;

        // Emit event
        event::emit(EscrowReleased {
            room_id,
            recipient: client,
            amount,
            timestamp: timestamp::now_seconds(),
        });
    }

    // ============================================================
    // VIEW FUNCTIONS
    // ============================================================

    #[view]
    /// Check if vault exists for room
    public fun vault_exists(room_id: u64): bool acquires VaultRegistry {
        let registry = borrow_global<VaultRegistry>(@aptosroom);
        table::contains(&registry.vaults, room_id)
    }

    #[view]
    /// Get task reward amount
    public fun get_task_reward(room_id: u64): u64 acquires VaultRegistry {
        let registry = borrow_global<VaultRegistry>(@aptosroom);
        let vault = table::borrow(&registry.vaults, room_id);
        vault.task_reward
    }

    // ============================================================
    // TEST-ONLY FUNCTIONS
    // ============================================================

    #[test_only]
    /// Initialize module for testing
    public fun init_for_test(account: &signer) {
        init_module(account);
    }

    #[test_only]
    /// Test helper to create vault
    public fun test_create_vault(
        client: address,
        room_id: u64,
        deposit: Coin<AptosCoin>,
        task_reward: u64,
    ) acquires VaultRegistry {
        create_vault(client, room_id, deposit, task_reward);
    }

    #[test_only]
    /// Test helper to unlock vault
    public fun test_unlock_vault(room_id: u64) acquires VaultRegistry {
        unlock_vault(room_id);
    }

    #[test_only]
    /// Test helper to release to winner
    public fun test_release_to_winner(
        room_id: u64,
        winner: address,
        amount: u64,
    ) acquires VaultRegistry {
        release_to_winner(room_id, winner, amount);
    }

    #[test_only]
    /// Test helper to refund to client
    public fun test_refund_to_client(room_id: u64) acquires VaultRegistry {
        refund_to_client(room_id);
    }
}
