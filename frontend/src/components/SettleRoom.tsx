"use client";

import { useWallet } from "@aptos-labs/wallet-adapter-react";
import { useState } from "react";
import {
    aptos,
    roomClient,
} from "@/lib/aptosroom";
import { submitSponsoredTransaction } from "@/lib/sponsoredTransaction";

interface SettleRoomProps {
    roomId: number;
    contributors: string[];
    onSettled: () => void;
}

export function SettleRoom({ roomId, contributors, onSettled }: SettleRoomProps) {
    const { connected, account, signTransaction, signAndSubmitTransaction } = useWallet();
    const [scores, setScores] = useState<Record<string, number>>({});
    const [loading, setLoading] = useState(false);
    const [step, setStep] = useState<"scores" | "settling">("scores");
    const [error, setError] = useState<string | null>(null);
    const [scoredContributors, setScoredContributors] = useState<Set<string>>(new Set());

    const formatAddress = (addr: string) => `${addr.slice(0, 6)}...${addr.slice(-4)}`;

    const updateScore = (addr: string, score: number) => {
        setScores((prev) => ({
            ...prev,
            [addr]: Math.min(100, Math.max(0, score)),
        }));
    };

    const handleSetScore = async (contributor: string) => {
        if (!connected) return;

        const score = scores[contributor];
        if (score === undefined || score < 0 || score > 100) {
            setError("Score must be between 0 and 100");
            return;
        }

        setLoading(true);
        setError(null);

        try {
            const contractAddress = process.env.NEXT_PUBLIC_CONTRACT_ADDRESS!;

            const response = await signAndSubmitTransaction({
                data: {
                    function: `${contractAddress}::room::set_client_score`,
                    functionArguments: [roomId, contributor, score],
                },
            });

            await aptos.waitForTransaction({ transactionHash: response.hash });
            setScoredContributors((prev) => new Set([...prev, contributor]));
        } catch (err) {
            console.error("Error setting score:", err);
            setError("Failed to set score");
        } finally {
            setLoading(false);
        }
    };

    const handleSetAllScores = async () => {
        setLoading(true);
        setError(null);

        try {
            for (const contributor of contributors) {
                if (scoredContributors.has(contributor)) continue;

                const score = scores[contributor] ?? 50; // Default score
                const contractAddress = process.env.NEXT_PUBLIC_CONTRACT_ADDRESS!;

                const response = await signAndSubmitTransaction({
                    data: {
                        function: `${contractAddress}::room::set_client_score`,
                        functionArguments: [roomId, contributor, score],
                    },
                });

                await aptos.waitForTransaction({ transactionHash: response.hash });
                setScoredContributors((prev) => new Set([...prev, contributor]));
            }
            setStep("settling");
        } catch (err) {
            console.error("Error setting scores:", err);
            setError("Failed to set all scores");
        } finally {
            setLoading(false);
        }
    };

    const handleApproveAndSettle = async () => {
        if (!connected) return;

        setLoading(true);
        setError(null);

        try {
            const contractAddress = process.env.NEXT_PUBLIC_CONTRACT_ADDRESS!;

            // 0. Check if tiers are computed (Safety net for rooms finalized before fix)
            const [tiersComputed] = await aptos.view({
                payload: {
                    function: `${contractAddress}::aggregation::are_tiers_computed`,
                    functionArguments: [roomId.toString()],
                },
            });

            if (!tiersComputed) {
                const aggResponse = await submitSponsoredTransaction({
                    accountAddress: account!.address.toString(),
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
                accountAddress: account!.address.toString(),
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
                    accountAddress: account!.address.toString(),
                    data: {
                        function: `${contractAddress}::settlement::approve_settlement`,
                        functionArguments: [roomId],
                    },
                    signAndSubmitTransaction,
                    signTransaction: (tx) => signTransaction(tx),
                });
                await aptos.waitForTransaction({ transactionHash: approveResponse.hash });
            }

            // 3. Execute
            const settleResponse = await submitSponsoredTransaction({
                accountAddress: account!.address.toString(),
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
            setError("Failed to settle room (Sim: " + (err as any).toString() + ")");
        } finally {
            setLoading(false);
        }
    };

    const allScored = contributors.every((c) => scoredContributors.has(c));

    return (
        <div className="space-y-4">
            <h4 className="font-medium">Settlement</h4>

            {error && <p className="text-red-400 text-sm">{error}</p>}

            {step === "scores" && (
                <>
                    <p className="text-sm text-gray-400">
                        Rate each contributor (0-100). Your score counts for <span className="text-cyan-400 font-medium">60%</span> of the final score, jury votes count for <span className="text-purple-400 font-medium">40%</span>.
                    </p>

                    <div className="space-y-3">
                        {contributors.map((addr) => (
                            <div key={addr} className="flex items-center gap-2">
                                <span className="font-mono text-sm flex-1">{formatAddress(addr)}</span>
                                <input
                                    type="number"
                                    value={scores[addr] ?? ""}
                                    onChange={(e) => updateScore(addr, parseInt(e.target.value) || 0)}
                                    min={0}
                                    max={100}
                                    placeholder="50"
                                    className="w-20 text-center"
                                    disabled={scoredContributors.has(addr)}
                                />
                                {scoredContributors.has(addr) ? (
                                    <span className="text-green-400 text-sm">✓</span>
                                ) : (
                                    <button
                                        onClick={() => handleSetScore(addr)}
                                        disabled={loading}
                                        className="btn btn-secondary text-xs py-1 px-2"
                                    >
                                        Set
                                    </button>
                                )}
                            </div>
                        ))}
                    </div>

                    <div className="flex gap-2">
                        <button
                            onClick={handleSetAllScores}
                            disabled={loading || allScored}
                            className="btn btn-secondary flex-1"
                        >
                            {loading ? "Setting..." : "Set All Scores"}
                        </button>
                        {allScored && (
                            <button
                                onClick={() => setStep("settling")}
                                className="btn btn-primary flex-1"
                            >
                                Continue to Settle
                            </button>
                        )}
                    </div>
                </>
            )}

            {step === "settling" && (
                <>
                    <p className="text-sm text-gray-400">
                        All scores set. Approve and execute settlement to distribute rewards.
                    </p>

                    <button
                        onClick={handleApproveAndSettle}
                        disabled={loading}
                        className="btn btn-primary w-full"
                    >
                        {loading ? "Settling..." : "Approve & Settle Room"}
                    </button>

                    <button
                        onClick={() => setStep("scores")}
                        disabled={loading}
                        className="btn btn-secondary w-full"
                    >
                        Back to Scores
                    </button>
                </>
            )}
        </div>
    );
}
