import { Aptos, AptosConfig, Network } from "@aptos-labs/ts-sdk";
import {
    KeycardClient,
    RoomClient,
    JuryClient,
    SettlementClient,
    JurorRegistryClient,
} from "@aptosroom/sdk";

// Contract address from environment
const CONTRACT_ADDRESS = process.env.NEXT_PUBLIC_CONTRACT_ADDRESS!;
const NETWORK = (process.env.NEXT_PUBLIC_APTOS_NETWORK || "testnet") as "testnet" | "mainnet" | "devnet";

// Gas Station Integration
import { GasStationClient, GasStationTransactionSubmitter } from "@aptos-labs/gas-station-client";

export let transactionSubmitter: GasStationTransactionSubmitter | undefined;

const GAS_STATION_API_KEY = process.env.NEXT_PUBLIC_GAS_STATION_API_KEY;

let pluginSettings = undefined;

if (GAS_STATION_API_KEY) {
    console.log("Initializing Gas Station Client...");
    const gasStationClient = new GasStationClient({
        network: NETWORK === "testnet" ? Network.TESTNET :
            NETWORK === "mainnet" ? Network.MAINNET : Network.DEVNET,
        apiKey: GAS_STATION_API_KEY,
    });
    transactionSubmitter = new GasStationTransactionSubmitter(gasStationClient);
    pluginSettings = {
        TRANSACTION_SUBMITTER: transactionSubmitter,
    };
} else {
    // console.warn("No Gas Station API Key found. Transactions will require user to pay gas.");
}

// Create Aptos client for the configured network
const config = new AptosConfig({
    network: NETWORK === "testnet" ? Network.TESTNET :
        NETWORK === "mainnet" ? Network.MAINNET : Network.DEVNET,
    pluginSettings,
} as any);

export const aptos = new Aptos(config);

// SDK Module Clients
export const keycardClient = new KeycardClient(aptos, CONTRACT_ADDRESS);
export const roomClient = new RoomClient(aptos, CONTRACT_ADDRESS);
export const juryClient = new JuryClient(aptos, CONTRACT_ADDRESS);
export const settlementClient = new SettlementClient(aptos, CONTRACT_ADDRESS);
export const registryClient = new JurorRegistryClient(aptos, CONTRACT_ADDRESS);

export async function getNextRoomId(): Promise<number> {
    try {
        console.log("Fetching RoomRegistry from", CONTRACT_ADDRESS);
        const resource = await aptos.getAccountResource({
            accountAddress: CONTRACT_ADDRESS,
            resourceType: `${CONTRACT_ADDRESS}::room::RoomRegistry`,
        });
        console.log("RoomRegistry resource:", resource);
        // SDK usually returns { type: "...", data: { ... } }
        const data = (resource as any).data || resource;
        const nextId = Number(data.next_id);

        if (isNaN(nextId)) {
            console.warn("Parsed next_id is NaN", data);
            return 50; // Fallback
        }

        console.log("Parsed next_id:", nextId);
        return nextId;
    } catch (e) {
        console.warn("Failed to fetch RoomRegistry, defaulting to 50", e);
        return 50;
    }
}


// Room state constants (matching contract)
export const ROOM_STATES = {
    INIT: 0,
    OPEN: 1,
    CLOSED: 2,
    JURY_ACTIVE: 3,
    JURY_REVEAL: 4,
    FINALIZED: 5,
    SETTLED: 6,
} as const;

export const STATE_LABELS: Record<number, string> = {
    [ROOM_STATES.INIT]: "Init",
    [ROOM_STATES.OPEN]: "Open",
    [ROOM_STATES.CLOSED]: "Closed",
    [ROOM_STATES.JURY_ACTIVE]: "Jury Active",
    [ROOM_STATES.JURY_REVEAL]: "Jury Reveal",
    [ROOM_STATES.FINALIZED]: "Finalized",
    [ROOM_STATES.SETTLED]: "Settled",
};

export const STATE_BADGES: Record<number, string> = {
    [ROOM_STATES.INIT]: "badge-init",
    [ROOM_STATES.OPEN]: "badge-open",
    [ROOM_STATES.CLOSED]: "badge-closed",
    [ROOM_STATES.JURY_ACTIVE]: "badge-jury",
    [ROOM_STATES.JURY_REVEAL]: "badge-jury",
    [ROOM_STATES.FINALIZED]: "badge-finalized",
    [ROOM_STATES.SETTLED]: "badge-settled",
};

// Tier constants
export const TIERS = {
    A: 1,
    B: 2,
    C: 3,
} as const;

export const TIER_LABELS: Record<number, string> = {
    [TIERS.A]: "Tier A (40%)",
    [TIERS.B]: "Tier B (30%)",
    [TIERS.C]: "Tier C (20%)",
};

// Get tier slot allocation based on contributor count
export function getTierSlots(contributorCount: number): { tierA: number; tierB: number } {
    if (contributorCount === 1) {
        return { tierA: 1, tierB: 0 };
    } else if (contributorCount === 2) {
        return { tierA: 1, tierB: 1 };
    } else if (contributorCount < 10) {
        return { tierA: 1, tierB: 2 };
    } else if (contributorCount <= 20) {
        return { tierA: 3, tierB: 4 };
    } else {
        return { tierA: 5, tierB: 7 };
    }
}

// Format APT amount (8 decimals)
export function formatApt(octas: bigint | number): string {
    const amount = Number(octas) / 100_000_000;
    return amount.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 4 });
}

// Parse APT to octas
export function parseApt(apt: string | number): bigint {
    return BigInt(Math.floor(Number(apt) * 100_000_000));
}

// Generate random salt for vote commitment
export function generateSalt(): Uint8Array {
    const salt = new Uint8Array(32);
    crypto.getRandomValues(salt);
    return salt;
}

// Local storage helpers for vote recovery
export interface StoredVote {
    tierA: string[];
    tierB: string[];
    salt: string; // hex encoded
    timestamp: number;
}

export function storeVote(roomId: number, address: string, vote: StoredVote): void {
    const key = `aptosroom_vote_${roomId}_${address}`;
    localStorage.setItem(key, JSON.stringify(vote));
}

export function getStoredVote(roomId: number, address: string): StoredVote | null {
    const key = `aptosroom_vote_${roomId}_${address}`;
    const data = localStorage.getItem(key);
    if (!data) return null;
    try {
        return JSON.parse(data);
    } catch {
        return null;
    }
}

export function clearStoredVote(roomId: number, address: string): void {
    const key = `aptosroom_vote_${roomId}_${address}`;
    localStorage.removeItem(key);
}

// Hex encoding/decoding
export function bytesToHex(bytes: Uint8Array): string {
    return Array.from(bytes)
        .map((b) => b.toString(16).padStart(2, "0"))
        .join("");
}

export function hexToBytes(hex: string): Uint8Array {
    const cleanHex = hex.startsWith("0x") ? hex.slice(2) : hex;
    const bytes = new Uint8Array(cleanHex.length / 2);
    for (let i = 0; i < bytes.length; i++) {
        bytes[i] = parseInt(cleanHex.substr(i * 2, 2), 16);
    }
    return bytes;
}
