"use client";

import { useState, useEffect, useCallback } from "react";
import { aptos, getNextRoomId, ROOM_STATES, STATE_LABELS, STATE_BADGES } from "@/lib/aptosroom";
import { enqueueRequest } from "@/lib/rateLimitedClient";

const CONTRACT_ADDRESS = process.env.NEXT_PUBLIC_CONTRACT_ADDRESS!;

export interface RoomSummary {
    id: number;
    state: number;
    category: string;
    contributorCount: number;
}

interface RoomListProps {
    onSelectRoom: (roomId: number) => void;
    selectedRoomId: number | null;
    refreshTrigger?: number;
}

// Direct view calls using only actual #[view] functions from the contract
async function viewGetState(roomId: number): Promise<number> {
    return enqueueRequest(async () => {
        const result = await aptos.view({
            payload: {
                function: `${CONTRACT_ADDRESS}::room::get_state`,
                functionArguments: [roomId.toString()],
            },
        });
        return Number(result[0]);
    });
}

async function viewGetCategory(roomId: number): Promise<string> {
    return enqueueRequest(async () => {
        const result = await aptos.view({
            payload: {
                function: `${CONTRACT_ADDRESS}::room::get_category`,
                functionArguments: [roomId.toString()],
            },
        });
        return result[0] as string;
    });
}

async function viewGetSubmissionCount(roomId: number): Promise<number> {
    return enqueueRequest(async () => {
        const result = await aptos.view({
            payload: {
                function: `${CONTRACT_ADDRESS}::room::get_submission_count`,
                functionArguments: [roomId.toString()],
            },
        });
        return Number(result[0]);
    });
}

export function RoomList({ onSelectRoom, selectedRoomId, refreshTrigger }: RoomListProps) {
    const [rooms, setRooms] = useState<RoomSummary[]>([]);
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState<string | null>(null);

    const fetchRooms = useCallback(async () => {
        setLoading(true);
        setError(null);

        try {
            const nextId = await enqueueRequest(() => getNextRoomId());
            console.log("RoomList: nextId =", nextId);

            if (nextId <= 1) {
                setRooms([]);
                return;
            }

            const MAX_ROOMS = 5;
            const startId = Math.max(1, nextId - MAX_ROOMS);
            const results: RoomSummary[] = [];

            // Fetch rooms ONE AT A TIME through the rate-limited queue
            for (let i = nextId - 1; i >= startId; i--) {
                try {
                    const state = await viewGetState(i);
                    const category = await viewGetCategory(i);
                    const contributorCount = await viewGetSubmissionCount(i);
                    results.push({ id: i, state, category, contributorCount });
                } catch (e) {
                    console.warn(`Failed to fetch room ${i}:`, e);
                }
            }
            console.log("RoomList: Found", results.length, "rooms");
            setRooms(results);
        } catch (err) {
            console.error("Error fetching rooms:", err);
            setError("Failed to load rooms");
        } finally {
            setLoading(false);
        }
    }, []);

    useEffect(() => {
        fetchRooms();
    }, [fetchRooms, refreshTrigger]);

    if (loading && rooms.length === 0) {
        return (
            <div className="card">
                <h2 className="text-lg font-semibold mb-4">Rooms</h2>
                <p className="text-gray-400 text-sm">Loading rooms...</p>
            </div>
        );
    }

    return (
        <div className="card">
            <div className="flex items-center justify-between mb-4">
                <h2 className="text-lg font-semibold">Rooms</h2>
                <button
                    onClick={fetchRooms}
                    className="text-sm text-cyan-400 hover:text-cyan-300"
                >
                    ↻ Refresh
                </button>
            </div>

            {error && (
                <p className="text-red-400 text-sm mb-3">{error}</p>
            )}

            {rooms.length === 0 ? (
                <p className="text-gray-400 text-sm">No rooms found. Create one to get started!</p>
            ) : (
                <div className="space-y-2 max-h-80 overflow-y-auto">
                    {rooms.map((room) => (
                        <button
                            key={room.id}
                            onClick={() => onSelectRoom(room.id)}
                            className={`w-full text-left p-3 rounded-lg border transition-colors ${selectedRoomId === room.id
                                ? "border-cyan-400 bg-cyan-400/10"
                                : "border-gray-700 hover:border-gray-600 bg-gray-800/50"
                                }`}
                        >
                            <div className="flex items-center justify-between">
                                <span className="font-medium">Room #{room.id}</span>
                                <span className={`badge ${STATE_BADGES[room.state]}`}>
                                    {STATE_LABELS[room.state]}
                                </span>
                            </div>
                            <div className="flex items-center justify-between mt-1 text-sm text-gray-400">
                                <span className="capitalize">{room.category}</span>
                                <span>{room.contributorCount} submissions</span>
                            </div>
                        </button>
                    ))}
                </div>
            )}
        </div>
    );
}

