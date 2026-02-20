"use client";

import { useWallet } from "@aptos-labs/wallet-adapter-react";
import { useState } from "react";
import { aptos } from "@/lib/aptosroom";
import { submitSponsoredTransaction, submitKeylessSponsoredTransaction } from "@/lib/sponsoredTransaction";
import { enqueueRequest } from "@/lib/rateLimitedClient";
import { useKeylessAuth } from "./KeylessAuthContext";

interface SettleRoomProps {
    roomId: number;
    contributors: string[];
    onSettled: () => void;
}

export function SettleRoom({ roomId, contributors, onSettled }: SettleRoomProps) {
    const { connected, account, signTransaction, signAndSubmitTransaction } = useWallet();
    const { keylessAccount, isKeylessUser } = useKeylessAuth();
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState<string | null>(null);

    const isAuthenticated = isKeylessUser || (connected && !!account);

    // Helper: sign and submit via keyless or wallet
    const signAndSubmit = async (functionName: string, args: any[]): Promise<string> => {
        const contractAddress = process.env.NEXT_PUBLIC_CONTRACT_ADDRESS!;
        const data = {
            function: `${contractAddress}::${functionName}` as `${string}::${string}::${string}`,
            functionArguments: args,
        };
        if (isKeylessUser && keylessAccount) {
            const response = await submitKeylessSponsoredTransaction({ keylessAccount, data });
            return response.hash;
        } else {
            const response = await submitSponsoredTransaction({
                accountAddress: account!.address.toString(),
                data: {
                    function: `${contractAddress}::${functionName}` as `${string}::${string}::${string}`,
                    functionArguments: args as any,
                },
                signAndSubmitTransaction,
                signTransaction: (tx) => signTransaction(tx),
            });
            return response.hash;
        }
    };

    const handleApproveAndSettle = async () => {
        if (!isAuthenticated) return;

        setLoading(true);
        setError(null);

        try {
            const contractAddress = process.env.NEXT_PUBLIC_CONTRACT_ADDRESS!;

            // 0. Check if tiers are computed (Safety net)
            const [tiersComputed] = await enqueueRequest(() => aptos.view({
                payload: {
                    function: `${contractAddress}::aggregation::are_tiers_computed`,
                    functionArguments: [roomId.toString()],
                },
            }));

            if (!tiersComputed) {
                const aggHash = await signAndSubmit("aggregation::aggregate_tier_votes", [roomId]);
                await aptos.waitForTransaction({ transactionHash: aggHash });
            }

            // 1. Process final scores (combine client + jury)
            const processHash = await signAndSubmit("aggregation::process_tier_final_scores", [roomId]);
            await aptos.waitForTransaction({ transactionHash: processHash });

            // 2. Approve (Idempotent check)
            const [isApproved] = await enqueueRequest(() => aptos.view({
                payload: {
                    function: `${contractAddress}::settlement::is_approved`,
                    functionArguments: [roomId.toString()],
                },
            }));

            if (!isApproved) {
                const approveHash = await signAndSubmit("settlement::approve_settlement", [roomId]);
                await aptos.waitForTransaction({ transactionHash: approveHash });
            }

            // 3. Execute settlement
            const settleHash = await signAndSubmit("settlement::execute_tier_settlement", [roomId]);
            await aptos.waitForTransaction({ transactionHash: settleHash });

            onSettled();
        } catch (err) {
            console.error("Error settling:", err);
            setError("Failed to settle room: " + (err as any).toString());
        } finally {
            setLoading(false);
        }
    };

    return (
        <div className="space-y-4">
            <h4 className="font-medium">Settlement</h4>

            {error && <p className="text-red-400 text-sm">{error}</p>}

            <p className="text-sm text-gray-400">
                Client scores were set during the CLOSED phase. Approve and execute settlement to distribute rewards based on the <span className="text-cyan-400 font-medium">60/40</span> Dual-Key Consensus.
            </p>

            {isKeylessUser && (
                <p className="text-xs text-blue-400">✨ Signed in with Google — settlement will be processed silently.</p>
            )}

            <button
                onClick={handleApproveAndSettle}
                disabled={loading}
                className="btn btn-primary w-full"
            >
                {loading ? "Settling..." : "Approve & Settle Room"}
            </button>
        </div>
    );
}
