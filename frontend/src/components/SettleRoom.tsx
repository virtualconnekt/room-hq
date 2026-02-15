"use client";

import { useWallet } from "@aptos-labs/wallet-adapter-react";
import { useState } from "react";
import { aptos } from "@/lib/aptosroom";
import { submitSponsoredTransaction } from "@/lib/sponsoredTransaction";

interface SettleRoomProps {
    roomId: number;
    contributors: string[];
    onSettled: () => void;
}

export function SettleRoom({ roomId, contributors, onSettled }: SettleRoomProps) {
    const { connected, account, signTransaction, signAndSubmitTransaction } = useWallet();
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState<string | null>(null);

    const handleApproveAndSettle = async () => {
        if (!connected || !account) return;

        setLoading(true);
        setError(null);

        try {
            const contractAddress = process.env.NEXT_PUBLIC_CONTRACT_ADDRESS!;

            // 0. Check if tiers are computed (Safety net)
            const [tiersComputed] = await aptos.view({
                payload: {
                    function: `${contractAddress}::aggregation::are_tiers_computed`,
                    functionArguments: [roomId.toString()],
                },
            });

            if (!tiersComputed) {
                const aggResponse = await submitSponsoredTransaction({
                    accountAddress: account.address.toString(),
                    data: {
                        function: `${contractAddress}::aggregation::aggregate_tier_votes`,
                        functionArguments: [roomId],
                    },
                    signAndSubmitTransaction,
                    signTransaction: (tx) => signTransaction(tx),
                });
                await aptos.waitForTransaction({ transactionHash: aggResponse.hash });
            }

            // 1. Process final scores (combine client + jury)
            const processResponse = await submitSponsoredTransaction({
                accountAddress: account.address.toString(),
                data: {
                    function: `${contractAddress}::aggregation::process_tier_final_scores`,
                    functionArguments: [roomId],
                },
                signAndSubmitTransaction,
                signTransaction: (tx) => signTransaction(tx),
            });
            await aptos.waitForTransaction({ transactionHash: processResponse.hash });

            // 2. Approve (Idempotent check)
            const [isApproved] = await aptos.view({
                payload: {
                    function: `${contractAddress}::settlement::is_approved`,
                    functionArguments: [roomId.toString()],
                },
            });

            if (!isApproved) {
                const approveResponse = await submitSponsoredTransaction({
                    accountAddress: account.address.toString(),
                    data: {
                        function: `${contractAddress}::settlement::approve_settlement`,
                        functionArguments: [roomId],
                    },
                    signAndSubmitTransaction,
                    signTransaction: (tx) => signTransaction(tx),
                });
                await aptos.waitForTransaction({ transactionHash: approveResponse.hash });
            }

            // 3. Execute settlement
            const settleResponse = await submitSponsoredTransaction({
                accountAddress: account.address.toString(),
                data: {
                    function: `${contractAddress}::settlement::execute_tier_settlement`,
                    functionArguments: [roomId],
                },
                signAndSubmitTransaction,
                signTransaction: (tx) => signTransaction(tx),
            });

            await aptos.waitForTransaction({ transactionHash: settleResponse.hash });
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
