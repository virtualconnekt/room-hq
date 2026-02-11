"use client";

import { useWallet } from "@aptos-labs/wallet-adapter-react";
import { useEffect, useState, useCallback } from "react";
import { keycardClient, aptos } from "@/lib/aptosroom";
import { submitSponsoredTransaction } from "@/lib/sponsoredTransaction";

interface KeycardData {
    hasKeycard: boolean;
    id?: string;
    tasksCompleted?: number;
    juryParticipations?: number;
    varianceFlags?: number;
    avgScore?: number;
}

export function KeycardPanel() {
    const { account, connected, signAndSubmitTransaction, signTransaction } = useWallet();
    const [keycard, setKeycard] = useState<KeycardData>({ hasKeycard: false });
    const [loading, setLoading] = useState(false);
    const [minting, setMinting] = useState(false);
    const [error, setError] = useState<string | null>(null);

    const fetchKeycard = useCallback(async () => {
        if (!connected || !account) return;

        setLoading(true);
        setError(null);

        try {
            const address = account.address.toString();
            const hasCard = await keycardClient.hasKeycard(address);

            if (hasCard) {
                const [id, tasks, jury, variance, score] = await Promise.all([
                    keycardClient.getKeycardId(address),
                    keycardClient.getTasksCompleted(address),
                    keycardClient.getJuryParticipations(address),
                    keycardClient.getVarianceFlags(address),
                    keycardClient.getAverageScore(address),
                ]);

                setKeycard({
                    hasKeycard: true,
                    id: id.toString(),
                    tasksCompleted: tasks,
                    juryParticipations: jury,
                    varianceFlags: variance,
                    avgScore: score,
                });
            } else {
                setKeycard({ hasKeycard: false });
            }
        } catch (err) {
            console.error("Error fetching keycard:", err);
            setError("Failed to fetch keycard data");
        } finally {
            setLoading(false);
        }
    }, [connected, account]);

    useEffect(() => {
        fetchKeycard();
    }, [fetchKeycard]);

    const handleMintKeycard = async () => {
        if (!connected || !account) return;

        setMinting(true);
        setError(null);

        try {
            const contractAddress = process.env.NEXT_PUBLIC_CONTRACT_ADDRESS!;

            const response = await submitSponsoredTransaction({
                accountAddress: account.address.toString(),
                data: {
                    function: `${contractAddress}::keycard::mint`,
                    functionArguments: [],
                },
                signAndSubmitTransaction,
                signTransaction,
            });

            // Wait for transaction confirmation
            await aptos.waitForTransaction({ transactionHash: response.hash });

            // Refresh keycard data
            await fetchKeycard();
        } catch (err) {
            console.error("Error minting keycard:", err);
            setError("Failed to mint keycard");
        } finally {
            setMinting(false);
        }
    };

    if (!connected) {
        return (
            <div className="card">
                <h2 className="text-lg font-semibold mb-2">Your Keycard</h2>
                <p className="text-gray-400 text-sm">Connect wallet to view keycard</p>
            </div>
        );
    }

    if (loading) {
        return (
            <div className="card">
                <h2 className="text-lg font-semibold mb-2">Your Keycard</h2>
                <p className="text-gray-400 text-sm">Loading...</p>
            </div>
        );
    }

    return (
        <div className="card">
            <h2 className="text-lg font-semibold mb-4">Your Keycard</h2>

            {error && (
                <p className="text-red-400 text-sm mb-3">{error}</p>
            )}

            {keycard.hasKeycard ? (
                <div className="space-y-3">
                    <div className="flex items-center justify-between">
                        <span className="text-gray-400 text-sm">ID</span>
                        <span className="font-mono text-sm">#{keycard.id}</span>
                    </div>

                    <div className="flex items-center justify-between">
                        <span className="text-gray-400 text-sm">Tasks Completed</span>
                        <span className="font-semibold">{keycard.tasksCompleted}</span>
                    </div>

                    <div className="flex items-center justify-between">
                        <span className="text-gray-400 text-sm">Avg Score</span>
                        <span className="font-semibold">
                            {keycard.avgScore !== undefined ? keycard.avgScore : "--"}
                        </span>
                    </div>

                    <div className="flex items-center justify-between">
                        <span className="text-gray-400 text-sm">Jury Participations</span>
                        <span className="font-semibold">{keycard.juryParticipations}</span>
                    </div>

                    <div className="flex items-center justify-between">
                        <span className="text-gray-400 text-sm">Variance Flags</span>
                        <span className={`font-semibold ${keycard.varianceFlags && keycard.varianceFlags > 0 ? 'text-yellow-400' : ''}`}>
                            {keycard.varianceFlags}
                        </span>
                    </div>

                    <div className="pt-2 border-t border-gray-700">
                        <span className="badge badge-open">✓ Active</span>
                    </div>
                </div>
            ) : (
                <div className="space-y-4">
                    <p className="text-gray-400 text-sm">
                        You need a Keycard to participate in AptosRoom. Mint one to get started.
                    </p>
                    <button
                        onClick={handleMintKeycard}
                        disabled={minting}
                        className="btn btn-primary w-full"
                    >
                        {minting ? "Minting..." : "Create Keycard"}
                    </button>
                </div>
            )}
        </div>
    );
}
