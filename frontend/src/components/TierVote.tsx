"use client";

import { useWallet } from "@aptos-labs/wallet-adapter-react";
import { useState, useEffect } from "react";
import {
    juryClient,
    aptos,
    getTierSlots,
    generateSalt,
    storeVote,
    getStoredVote,
    clearStoredVote,
    bytesToHex,
    hexToBytes,
} from "@/lib/aptosroom";
import { submitSponsoredTransaction } from "@/lib/sponsoredTransaction";

interface TierVoteProps {
    roomId: number;
    contributors: string[];
    onVoteCommitted: () => void;
    isReveal?: boolean;
}

export function TierVote({ roomId, contributors, onVoteCommitted, isReveal = false }: TierVoteProps) {
    const { account, connected, signAndSubmitTransaction, signTransaction } = useWallet();
    const [tierA, setTierA] = useState<Set<string>>(new Set());
    const [tierB, setTierB] = useState<Set<string>>(new Set());
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState<string | null>(null);
    const [hasCommitted, setHasCommitted] = useState(false);
    const [hasRevealed, setHasRevealed] = useState(false);

    const slots = getTierSlots(contributors.length);

    // Load stored vote data on mount
    useEffect(() => {
        if (!connected || !account) return;

        const checkStatus = async () => {
            try {
                const committed = await juryClient.hasTierVote(roomId, account.address.toString());
                setHasCommitted(committed);

                if (committed) {
                    const revealed = await juryClient.isTierVoteRevealed(roomId, account.address.toString());
                    setHasRevealed(revealed);
                }

                // Load stored vote for reveal
                const stored = getStoredVote(roomId, account.address.toString());
                if (stored) {
                    setTierA(new Set(stored.tierA));
                    setTierB(new Set(stored.tierB));
                }
            } catch (err) {
                console.error("Error checking vote status:", err);
            }
        };

        checkStatus();
    }, [roomId, account, connected]);

    const toggleTierA = (addr: string) => {
        const newSet = new Set(tierA);
        if (newSet.has(addr)) {
            newSet.delete(addr);
        } else if (newSet.size < slots.tierA) {
            // Remove from B if in B
            const newB = new Set(tierB);
            newB.delete(addr);
            setTierB(newB);
            newSet.add(addr);
        }
        setTierA(newSet);
    };

    const toggleTierB = (addr: string) => {
        // Can't add if already in A
        if (tierA.has(addr)) return;

        const newSet = new Set(tierB);
        if (newSet.has(addr)) {
            newSet.delete(addr);
        } else if (newSet.size < slots.tierB) {
            newSet.add(addr);
        }
        setTierB(newSet);
    };

    const handleCommit = async () => {
        if (!connected || !account) return;

        if (tierA.size !== slots.tierA) {
            setError(`Please select exactly ${slots.tierA} contributor(s) for Tier A`);
            return;
        }
        if (tierB.size !== slots.tierB) {
            setError(`Please select exactly ${slots.tierB} contributor(s) for Tier B`);
            return;
        }

        setLoading(true);
        setError(null);

        try {
            const tierAList = Array.from(tierA);
            const tierBList = Array.from(tierB);
            const salt = generateSalt();

            // Compute commit hash
            const voteHash = juryClient.computeTierVoteHash(tierAList, tierBList, salt);

            // Store vote locally for reveal
            storeVote(roomId, account.address.toString(), {
                tierA: tierAList,
                tierB: tierBList,
                salt: bytesToHex(salt),
                timestamp: Date.now(),
            });

            const contractAddress = process.env.NEXT_PUBLIC_CONTRACT_ADDRESS!;

            // Encrypt data for recovery (store on-chain)
            let encryptedData: number[] = [];
            if (account.publicKey) {
                try {
                    // account.publicKey is usually hex string
                    const pubKeyBytes = hexToBytes(account.publicKey.toString());
                    const encrypted = juryClient.encryptTierVote({
                        tierA: tierAList,
                        tierB: tierBList,
                        salt: salt
                    }, pubKeyBytes);
                    encryptedData = Array.from(encrypted);
                } catch (e) {
                    console.warn("Failed to encrypt vote data, proceeding without on-chain backup:", e);
                }
            }

            const response = await submitSponsoredTransaction({
                accountAddress: account.address.toString(),
                data: {
                    function: `${contractAddress}::jury::commit_tier_vote`,
                    functionArguments: [
                        roomId,
                        Array.from(voteHash),
                        encryptedData,
                    ],
                },
                signAndSubmitTransaction,
                signTransaction,
            });

            await aptos.waitForTransaction({ transactionHash: response.hash });
            setHasCommitted(true);
            onVoteCommitted();
        } catch (err) {
            console.error("Error committing vote:", err);
            setError("Failed to commit vote");
        } finally {
            setLoading(false);
        }
    };

    const handleReveal = async () => {
        if (!connected || !account) return;

        const stored = getStoredVote(roomId, account.address.toString());
        if (!stored) {
            setError("No stored vote found. Cannot reveal.");
            return;
        }

        setLoading(true);
        setError(null);

        try {
            const contractAddress = process.env.NEXT_PUBLIC_CONTRACT_ADDRESS!;
            const salt = hexToBytes(stored.salt);

            const response = await submitSponsoredTransaction({
                accountAddress: account.address.toString(),
                data: {
                    function: `${contractAddress}::jury::reveal_tier_vote`,
                    functionArguments: [
                        roomId,
                        stored.tierA,
                        stored.tierB,
                        Array.from(salt),
                    ],
                },
                signAndSubmitTransaction,
                signTransaction,
            });

            await aptos.waitForTransaction({ transactionHash: response.hash });

            // Clear stored vote after successful reveal
            clearStoredVote(roomId, account.address.toString());
            setHasRevealed(true);
            onVoteCommitted();
        } catch (err) {
            console.error("Error revealing vote:", err);
            setError("Failed to reveal vote. Make sure your stored data matches.");
        } finally {
            setLoading(false);
        }
    };

    const formatAddress = (addr: string) => `${addr.slice(0, 6)}...${addr.slice(-4)}`;

    // Already revealed
    if (hasRevealed) {
        return (
            <div className="bg-green-500/10 border border-green-500/30 rounded-lg p-4 text-center">
                <span className="text-green-400">✓ Vote Revealed</span>
            </div>
        );
    }

    // Reveal mode
    if (isReveal) {
        if (!hasCommitted) {
            return (
                <div className="bg-yellow-500/10 border border-yellow-500/30 rounded-lg p-4 text-center">
                    <span className="text-yellow-400">You haven&apos;t committed a vote</span>
                </div>
            );
        }

        return (
            <div className="space-y-4">
                <h4 className="font-medium">Reveal Your Vote</h4>
                {error && <p className="text-red-400 text-sm">{error}</p>}

                <p className="text-sm text-gray-400">
                    Click below to reveal your stored tier selections.
                </p>

                <button
                    onClick={handleReveal}
                    disabled={loading}
                    className="btn btn-primary w-full"
                >
                    {loading ? "Revealing..." : "Reveal Vote"}
                </button>
            </div>
        );
    }

    // Already committed, waiting for reveal
    if (hasCommitted) {
        return (
            <div className="bg-blue-500/10 border border-blue-500/30 rounded-lg p-4 text-center">
                <span className="text-blue-400">✓ Vote Committed - Waiting for reveal phase</span>
            </div>
        );
    }

    // Commit mode
    return (
        <div className="space-y-4">
            <h4 className="font-medium">Commit Tier Vote</h4>

            {error && <p className="text-red-400 text-sm">{error}</p>}

            <div className="text-sm text-gray-400">
                <p>Contributors: {contributors.length}</p>
                <p>Tier A Slots: {tierA.size}/{slots.tierA} | Tier B Slots: {tierB.size}/{slots.tierB}</p>
            </div>

            <div className="space-y-2">
                <div className="text-sm font-medium text-purple-400 mb-1">
                    Select Tier A (Best - 40% score)
                </div>
                {contributors.map((addr) => (
                    <label
                        key={`a-${addr}`}
                        className={`flex items-center gap-2 p-2 rounded border cursor-pointer transition-colors ${tierA.has(addr)
                            ? "border-purple-500 bg-purple-500/10"
                            : tierB.has(addr)
                                ? "border-gray-700 bg-gray-800 opacity-50"
                                : "border-gray-700 hover:border-gray-600"
                            }`}
                    >
                        <input
                            type="checkbox"
                            checked={tierA.has(addr)}
                            onChange={() => toggleTierA(addr)}
                            disabled={tierB.has(addr)}
                            className="accent-purple-500"
                        />
                        <span className="font-mono text-sm">{formatAddress(addr)}</span>
                        {tierA.has(addr) && <span className="ml-auto text-purple-400 text-xs">Tier A</span>}
                    </label>
                ))}
            </div>

            <div className="space-y-2">
                <div className="text-sm font-medium text-blue-400 mb-1">
                    Select Tier B (Good - 30% score)
                </div>
                {contributors.map((addr) => (
                    <label
                        key={`b-${addr}`}
                        className={`flex items-center gap-2 p-2 rounded border cursor-pointer transition-colors ${tierB.has(addr)
                            ? "border-blue-500 bg-blue-500/10"
                            : tierA.has(addr)
                                ? "border-gray-700 bg-gray-800 opacity-50"
                                : "border-gray-700 hover:border-gray-600"
                            }`}
                    >
                        <input
                            type="checkbox"
                            checked={tierB.has(addr)}
                            onChange={() => toggleTierB(addr)}
                            disabled={tierA.has(addr)}
                            className="accent-blue-500"
                        />
                        <span className="font-mono text-sm">{formatAddress(addr)}</span>
                        {tierB.has(addr) && <span className="ml-auto text-blue-400 text-xs">Tier B</span>}
                        {tierA.has(addr) && <span className="ml-auto text-purple-400 text-xs">In A</span>}
                    </label>
                ))}
            </div>

            <p className="text-xs text-gray-500">
                Remaining contributors ({contributors.length - tierA.size - tierB.size}) will be Tier C (20% score)
            </p>

            <button
                onClick={handleCommit}
                disabled={loading || tierA.size !== slots.tierA || tierB.size !== slots.tierB}
                className="btn btn-primary w-full"
            >
                {loading ? "Committing..." : "Commit Vote"}
            </button>
        </div>
    );
}
