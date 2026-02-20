/**
 * POST /api/jury-phase
 * Submits jury::start_jury_phase_random using the deployer's private key.
 *
 * This is needed because #[randomness] entry functions cannot have a fee payer,
 * so the Gas Station cannot sponsor them. The deployer account pays gas instead.
 *
 * Body: { roomId: number, eligibleJurors: string[], jurySize: number }
 */
import { NextRequest, NextResponse } from "next/server";
import { Aptos, AptosConfig, Network, Account, Ed25519PrivateKey } from "@aptos-labs/ts-sdk";

const NETWORK = (process.env.NEXT_PUBLIC_APTOS_NETWORK || "testnet") as "testnet" | "mainnet" | "devnet";
const CONTRACT_ADDRESS = process.env.NEXT_PUBLIC_CONTRACT_ADDRESS!;
const DEPLOYER_PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY;

const network =
    NETWORK === "testnet" ? Network.TESTNET :
        NETWORK === "mainnet" ? Network.MAINNET :
            Network.DEVNET;

const aptos = new Aptos(new AptosConfig({ network }));

export async function POST(req: NextRequest) {
    if (!DEPLOYER_PRIVATE_KEY) {
        return NextResponse.json({ error: "Server not configured: missing DEPLOYER_PRIVATE_KEY" }, { status: 500 });
    }

    let body: { roomId: number; eligibleJurors: string[]; jurySize: number };
    try {
        body = await req.json();
    } catch {
        return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
    }

    const { roomId, eligibleJurors, jurySize } = body;
    if (roomId === undefined || !Array.isArray(eligibleJurors) || jurySize === undefined) {
        return NextResponse.json({ error: "Missing required fields: roomId, eligibleJurors, jurySize" }, { status: 400 });
    }

    try {
        const privateKey = new Ed25519PrivateKey(DEPLOYER_PRIVATE_KEY);
        const deployer = Account.fromPrivateKey({ privateKey });

        const transaction = await aptos.transaction.build.simple({
            sender: deployer.accountAddress,
            data: {
                function: `${CONTRACT_ADDRESS}::jury::start_jury_phase_random`,
                functionArguments: [BigInt(roomId), eligibleJurors, BigInt(jurySize)],
            },
        });

        const committed = await aptos.signAndSubmitTransaction({
            signer: deployer,
            transaction,
        });

        await aptos.waitForTransaction({ transactionHash: committed.hash });

        return NextResponse.json({ hash: committed.hash });
    } catch (err: any) {
        console.error("Error submitting jury phase:", err);
        return NextResponse.json({ error: err?.message || "Transaction failed" }, { status: 500 });
    }
}
