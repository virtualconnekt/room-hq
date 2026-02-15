"use client";

import { useWallet } from "@aptos-labs/wallet-adapter-react";
import { useState, useEffect, useCallback } from "react";
import {
    aptos,
    ROOM_STATES,
    STATE_LABELS,
    STATE_BADGES,
} from "@/lib/aptosroom";
import { submitSponsoredTransaction } from "@/lib/sponsoredTransaction";
import { TierVote } from "./TierVote";
import { SettleRoom } from "./SettleRoom";

const CONTRACT_ADDRESS = process.env.NEXT_PUBLIC_CONTRACT_ADDRESS!;

interface RoomDetailProps {
    roomId: number;
    onAction: () => void;
}

interface RoomData {
    id: number;
    state: number;
    client: string;
    category: string;
    contributors: string[];
    juryPool: string[];
    submissions: Record<string, string>; // contributor address -> submission text
}

// Direct view function helpers (only using actual #[view] functions)
async function viewFn(fnName: string, args: string[], moduleName = "room"): Promise<any[]> {
    return aptos.view({
        payload: {
            function: `${CONTRACT_ADDRESS}::${moduleName}::${fnName}` as `${string}::${string}::${string}`,
            functionArguments: args,
        },
    });
}

export function RoomDetail({ roomId, onAction }: RoomDetailProps) {
    const { account, connected, signAndSubmitTransaction, signTransaction } = useWallet();
    const [room, setRoom] = useState<RoomData | null>(null);
    const [loading, setLoading] = useState(true);
    const [actionLoading, setActionLoading] = useState(false);
    const [error, setError] = useState<string | null>(null);
    const [submitHash, setSubmitHash] = useState("");
    const [clientScores, setClientScores] = useState<Record<string, number>>({});
    const [scoredContributors, setScoredContributors] = useState<Set<string>>(new Set());
    const fetchRoomData = useCallback(async () => {
        setLoading(true);
        setError(null);

        try {
            const rid = roomId.toString();
            const [stateRes, clientRes, categoryRes, contributorsRes, juryRes] = await Promise.all([
                viewFn("get_state", [rid]),
                viewFn("get_client", [rid]),
                viewFn("get_category", [rid]),
                viewFn("get_contributor_list", [rid]),
                viewFn("get_jury_pool", [rid]).catch(() => [[]]),
            ]);

            const contributors = (contributorsRes[0] as string[]) || [];

            // Fetch submission data for each contributor
            const submissions: Record<string, string> = {};
            await Promise.all(
                contributors.map(async (addr) => {
                    try {
                        const [dataRes] = await viewFn("get_submission_data_hash", [rid, addr]);
                        // dataRes is hex string like "0x68747470..." — decode to UTF-8
                        const hexStr = String(dataRes);
                        if (hexStr.startsWith("0x")) {
                            const bytes = new Uint8Array(
                                hexStr.slice(2).match(/.{1,2}/g)!.map((b: string) => parseInt(b, 16))
                            );
                            submissions[addr] = new TextDecoder().decode(bytes);
                        } else if (Array.isArray(dataRes)) {
                            // If returned as number array
                            const bytes = new Uint8Array(dataRes as number[]);
                            submissions[addr] = new TextDecoder().decode(bytes);
                        } else {
                            submissions[addr] = hexStr;
                        }
                    } catch {
                        submissions[addr] = "";
                    }
                })
            );

            setRoom({
                id: roomId,
                state: Number(stateRes[0]),
                client: stateRes[0] !== undefined ? String(clientRes[0]) : "",
                category: String(categoryRes[0]),
                contributors,
                juryPool: (juryRes[0] as string[]) || [],
                submissions,
            });
        } catch (err) {
            console.error("Error fetching room:", err);
            setError("Failed to load room data");
        } finally {
            setLoading(false);
        }
    }, [roomId]);

    useEffect(() => {
        fetchRoomData();
    }, [fetchRoomData]);

    const executeAction = async (functionName: string, args: unknown[] = []) => {
        if (!connected || !account) return;

        setActionLoading(true);
        setError(null);

        try {
            const contractAddress = process.env.NEXT_PUBLIC_CONTRACT_ADDRESS!;

            const response = await submitSponsoredTransaction({
                accountAddress: account.address.toString(),
                data: {
                    function: `${contractAddress}::${functionName}` as `${string}::${string}::${string}`,
                    functionArguments: args as any,
                },
                signAndSubmitTransaction,
                signTransaction,
            });

            await aptos.waitForTransaction({ transactionHash: response.hash });
            await fetchRoomData();
            onAction();
        } catch (err) {
            console.error(`Error executing ${functionName}:`, err);
            setError(`Failed to execute action`);
        } finally {
            setActionLoading(false);
        }
    };

    const handleOpenRoom = () => executeAction("room::open_room", [roomId]);
    const handleCloseRoom = () => {
        // Pass contributors as eligible jurors, jury_size=1 for testnet
        const eligibleJurors = room?.contributors || [];
        const jurySize = Math.min(eligibleJurors.length, 1); // Use 1 for testnet (min jurors)
        executeAction("room::close_room_with_jury", [roomId, eligibleJurors, jurySize]);
    };
    const handleStartJuryPhase = () => executeAction("room::start_jury_phase", [roomId]);
    const handleStartRevealPhase = () => executeAction("room::start_reveal_phase", [roomId]);

    const handleSetClientScore = async (contributor: string) => {
        if (!connected || !account) return;
        const score = clientScores[contributor];
        if (score === undefined || score < 0 || score > 100) {
            setError("Score must be between 0 and 100");
            return;
        }
        setActionLoading(true);
        setError(null);
        try {
            const response = await signAndSubmitTransaction({
                data: {
                    function: `${CONTRACT_ADDRESS}::room::set_client_score`,
                    functionArguments: [roomId, contributor, score],
                },
            });
            await aptos.waitForTransaction({ transactionHash: response.hash });
            setScoredContributors(prev => new Set([...prev, contributor]));
        } catch (err: any) {
            console.error("Error setting client score:", err);
            setError(`Failed to set score: ${err?.message || err}`);
        } finally {
            setActionLoading(false);
        }
    };
    const handleFinalizeRoom = async () => {
        if (!connected || !account) {
            setError("Wallet not connected. Please reconnect.");
            return;
        }

        setActionLoading(true);
        setError(null);
        const contractAddress = process.env.NEXT_PUBLIC_CONTRACT_ADDRESS!;

        try {
            // 1. Check if tiers are computed
            const [areTiersComputed] = await viewFn("are_tiers_computed", [roomId.toString()], "aggregation");

            if (!areTiersComputed) {
                // 2. Aggregate tier votes first
                console.log("Aggregating tier votes...");
                const aggResponse = await submitSponsoredTransaction({
                    accountAddress: account.address.toString(),
                    data: {
                        function: `${contractAddress}::aggregation::aggregate_tier_votes` as `${string}::${string}::${string}`,
                        functionArguments: [roomId] as any,
                    },
                    signAndSubmitTransaction,
                    signTransaction,
                });
                await aptos.waitForTransaction({ transactionHash: aggResponse.hash });
                console.log("Tier votes aggregated successfully.");
            }

            // 3. Finalize room
            console.log("Finalizing room...");
            const finalizeResponse = await submitSponsoredTransaction({
                accountAddress: account.address.toString(),
                data: {
                    function: `${contractAddress}::room::finalize_room` as `${string}::${string}::${string}`,
                    functionArguments: [roomId] as any,
                },
                signAndSubmitTransaction,
                signTransaction,
            });
            await aptos.waitForTransaction({ transactionHash: finalizeResponse.hash });
            console.log("Room finalized successfully.");

            await fetchRoomData();
            onAction();
        } catch (err: any) {
            console.error("Error finalizing:", err);
            const msg = err?.message || err?.toString() || "Unknown error";
            setError(`Failed to finalize room: ${msg}`);
        } finally {
            setActionLoading(false);
        }
    };

    const handleSubmitEntry = async () => {
        if (!submitHash.trim()) {
            setError("Please enter a submission hash");
            return;
        }
        const encoder = new TextEncoder();
        const hashBytes = Array.from(encoder.encode(submitHash));
        await executeAction("room::submit_entry", [roomId, hashBytes]);
        setSubmitHash("");
    };

    if (loading) {
        return (
            <div className="card">
                <p className="text-gray-400">Loading room #{roomId}...</p>
            </div>
        );
    }

    if (!room) {
        return (
            <div className="card">
                <p className="text-red-400">Room not found</p>
            </div>
        );
    }

    const isClient = connected && account && account.address.toString().toLowerCase() === room.client.toLowerCase();
    const isContributor = connected && account && room.contributors.some(
        c => c.toLowerCase() === account.address.toString().toLowerCase()
    );
    const isJuror = connected && account && room.juryPool.some(
        j => j.toLowerCase() === account.address.toString().toLowerCase()
    );

    const formatAddress = (addr: string) => `${addr.slice(0, 6)}...${addr.slice(-4)}`;

    return (
        <div className="card">
            <div className="flex items-center justify-between mb-4">
                <h2 className="text-lg font-semibold">Room #{room.id}</h2>
                <span className={`badge ${STATE_BADGES[room.state]}`}>
                    {STATE_LABELS[room.state]}
                </span>
            </div>

            {error && (
                <p className="text-red-400 text-sm mb-3">{error}</p>
            )}

            {/* Room Info */}
            <div className="space-y-2 mb-4 text-sm">
                <div className="flex justify-between">
                    <span className="text-gray-400">Client</span>
                    <span className="font-mono">
                        {formatAddress(room.client)}
                        {isClient && <span className="text-cyan-400 ml-2">(You)</span>}
                    </span>
                </div>
                <div className="flex justify-between">
                    <span className="text-gray-400">Category</span>
                    <span className="capitalize">{room.category}</span>
                </div>
                <div className="flex justify-between">
                    <span className="text-gray-400">Contributors</span>
                    <span>{room.contributors.length}</span>
                </div>
                {room.juryPool.length > 0 && (
                    <div className="flex justify-between">
                        <span className="text-gray-400">Jury Size</span>
                        <span>{room.juryPool.length}</span>
                    </div>
                )}
            </div>

            {/* Role Indicator */}
            <div className="flex gap-2 mb-4">
                {isClient && <span className="text-xs px-2 py-1 bg-purple-500/20 text-purple-400 rounded">Client</span>}
                {isContributor && <span className="text-xs px-2 py-1 bg-green-500/20 text-green-400 rounded">Contributor</span>}
                {isJuror && <span className="text-xs px-2 py-1 bg-blue-500/20 text-blue-400 rounded">Juror</span>}
            </div>

            {/* State-Specific Actions */}
            <div className="border-t border-gray-700 pt-4 space-y-4">

                {/* INIT: Client can open room */}
                {room.state === ROOM_STATES.INIT && isClient && (
                    <button
                        onClick={handleOpenRoom}
                        disabled={actionLoading}
                        className="btn btn-primary w-full"
                    >
                        {actionLoading ? "Opening..." : "Open Room for Submissions"}
                    </button>
                )}

                {/* OPEN: Contributors can submit */}
                {room.state === ROOM_STATES.OPEN && connected && !isContributor && (
                    <div className="space-y-2">
                        <input
                            type="text"
                            value={submitHash}
                            onChange={(e) => setSubmitHash(e.target.value)}
                            placeholder="Enter your submission hash or description"
                            className="w-full"
                        />
                        <button
                            onClick={handleSubmitEntry}
                            disabled={actionLoading}
                            className="btn btn-primary w-full"
                        >
                            {actionLoading ? "Submitting..." : "Submit Entry"}
                        </button>
                    </div>
                )}

                {/* OPEN: Client can close */}
                {room.state === ROOM_STATES.OPEN && isClient && (
                    <button
                        onClick={handleCloseRoom}
                        disabled={actionLoading}
                        className="btn btn-secondary w-full"
                    >
                        {actionLoading ? "Closing..." : "Close Room"}
                    </button>
                )}

                {/* CLOSED: Client scores contributors, then starts jury phase */}
                {room.state === ROOM_STATES.CLOSED && isClient && (
                    <div className="space-y-4">
                        <p className="text-sm text-gray-400">
                            Rate each contributor (0-100). Your score counts for <span className="text-cyan-400 font-medium">60%</span> of the final score, jury votes count for <span className="text-purple-400 font-medium">40%</span>.
                        </p>

                        <div className="space-y-2">
                            {room.contributors.map((addr) => (
                                <div key={addr} className="flex items-center gap-2">
                                    <span className="font-mono text-sm flex-1">{addr.slice(0, 6)}...{addr.slice(-4)}</span>
                                    <input
                                        type="number"
                                        min={0}
                                        max={100}
                                        placeholder="50"
                                        className="w-20 text-center"
                                        disabled={actionLoading || scoredContributors.has(addr)}
                                        value={clientScores[addr] ?? ""}
                                        onChange={(e) => setClientScores(prev => ({ ...prev, [addr]: Math.min(100, Math.max(0, parseInt(e.target.value) || 0)) }))}
                                    />
                                    {scoredContributors.has(addr) ? (
                                        <span className="text-green-400 text-sm">✓</span>
                                    ) : (
                                        <button
                                            onClick={() => handleSetClientScore(addr)}
                                            disabled={actionLoading}
                                            className="btn btn-secondary text-xs py-1 px-2"
                                        >
                                            {actionLoading ? "..." : "Set"}
                                        </button>
                                    )}
                                </div>
                            ))}
                        </div>

                        <button
                            onClick={handleStartJuryPhase}
                            disabled={actionLoading || !room.contributors.every(c => scoredContributors.has(c))}
                            className="btn btn-primary w-full"
                        >
                            {actionLoading ? "Starting..." : room.contributors.every(c => scoredContributors.has(c))
                                ? "Start Jury Phase"
                                : `Score all contributors first (${scoredContributors.size}/${room.contributors.length})`}
                        </button>
                    </div>
                )}

                {/* JURY_ACTIVE: Jury commits */}
                {room.state === ROOM_STATES.JURY_ACTIVE && isJuror && (
                    <TierVote
                        roomId={roomId}
                        contributors={room.contributors}
                        onVoteCommitted={fetchRoomData}
                    />
                )}

                {/* JURY_ACTIVE: Client can start reveal */}
                {room.state === ROOM_STATES.JURY_ACTIVE && isClient && (
                    <button
                        onClick={handleStartRevealPhase}
                        disabled={actionLoading}
                        className="btn btn-secondary w-full mt-2"
                    >
                        {actionLoading ? "Starting..." : "Start Reveal Phase"}
                    </button>
                )}

                {/* JURY_REVEAL: Jury reveals */}
                {room.state === ROOM_STATES.JURY_REVEAL && isJuror && (
                    <TierVote
                        roomId={roomId}
                        contributors={room.contributors}
                        onVoteCommitted={fetchRoomData}
                        isReveal={true}
                    />
                )}

                {/* JURY_REVEAL: Client can finalize */}
                {room.state === ROOM_STATES.JURY_REVEAL && isClient && (
                    <button
                        onClick={handleFinalizeRoom}
                        disabled={actionLoading}
                        className="btn btn-secondary w-full mt-2"
                    >
                        {actionLoading ? "Finalizing..." : "Finalize Room"}
                    </button>
                )}

                {/* FINALIZED: Client settles (scores already set) */}
                {room.state === ROOM_STATES.FINALIZED && isClient && (
                    <SettleRoom
                        roomId={roomId}
                        contributors={room.contributors}
                        onSettled={fetchRoomData}
                    />
                )}

                {/* SETTLED: Show results */}
                {room.state === ROOM_STATES.SETTLED && (
                    <div className="text-center py-4">
                        <span className="text-2xl">✅</span>
                        <p className="text-green-400 font-semibold mt-2">Room Settled</p>
                        <p className="text-gray-400 text-sm">Rewards have been distributed</p>
                    </div>
                )}

                {/* Show contributors & their submissions */}
                {room.contributors.length > 0 && (
                    <div className="mt-4">
                        <h4 className="text-sm font-medium text-gray-400 mb-2">Contributors & Submissions</h4>
                        <div className="space-y-3">
                            {room.contributors.map((addr) => {
                                const submissionText = room.submissions[addr] || "";
                                const isUrl = submissionText.startsWith("http://") || submissionText.startsWith("https://");
                                return (
                                    <div key={addr} className="p-2 bg-gray-800/50 rounded border border-gray-700">
                                        <div className="text-xs font-mono text-gray-300">
                                            {formatAddress(addr)}
                                            {connected && account && addr.toLowerCase() === account.address.toString().toLowerCase() && (
                                                <span className="text-cyan-400 ml-2">(You)</span>
                                            )}
                                        </div>
                                        {submissionText && (
                                            <div className="mt-1">
                                                {isUrl ? (
                                                    <a
                                                        href={submissionText}
                                                        target="_blank"
                                                        rel="noopener noreferrer"
                                                        className="text-xs text-blue-400 hover:underline break-all"
                                                    >
                                                        🔗 {submissionText}
                                                    </a>
                                                ) : (
                                                    <p className="text-xs text-gray-400 break-all">📄 {submissionText}</p>
                                                )}
                                            </div>
                                        )}
                                    </div>
                                );
                            })}
                        </div>
                    </div>
                )}

                {/* Show jury pool if exists */}
                {room.juryPool.length > 0 && (
                    <div className="mt-4">
                        <h4 className="text-sm font-medium text-gray-400 mb-2">Jury Pool</h4>
                        <div className="space-y-1">
                            {room.juryPool.map((addr) => (
                                <div key={addr} className="text-xs font-mono text-gray-300">
                                    {formatAddress(addr)}
                                    {connected && account && addr.toLowerCase() === account.address.toString().toLowerCase() && (
                                        <span className="text-blue-400 ml-2">(You)</span>
                                    )}
                                </div>
                            ))}
                        </div>
                    </div>
                )}
            </div>
        </div>
    );
}
