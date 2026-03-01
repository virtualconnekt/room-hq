"use client";

import { useState, useCallback } from "react";
import type { RoomSummary } from "@/components/RoomList";
import {
  WalletConnect,
  KeycardPanel,
  RoomList,
  RoomDetail,
  CreateRoom
} from "@/components";

export default function Dashboard() {
  const [selectedRoomId, setSelectedRoomId] = useState<number | null>(null);
  const [refreshTrigger, setRefreshTrigger] = useState(0);

  const [optimisticRooms, setOptimisticRooms] = useState<RoomSummary[]>([]);

  const handleRoomCreated = useCallback((room: { category: string; reward: string; creator: string }) => {
    // 1. Immediately inject the new room optimistically (no id yet, use -1 as placeholder)
    const optimistic: RoomSummary = {
      id: -Date.now(), // temp unique negative id
      state: 1,
      category: room.category,
      contributorCount: 0,
    };
    setOptimisticRooms((prev) => [optimistic, ...prev]);

    // 2. After 6s (one indexer poll cycle), trigger a real fetch which will replace optimistic data
    setTimeout(() => {
      setOptimisticRooms([]);
      setRefreshTrigger((prev) => prev + 1);
    }, 6000);
  }, []);

  const handleRoomAction = useCallback(() => {
    setRefreshTrigger((prev) => prev + 1);
  }, []);

  return (
    <div className="min-h-screen">
      {/* Header */}
      <header className="border-b border-gray-800 sticky top-0 bg-[#0a0a0a] z-10">
        <div className="max-w-7xl mx-auto px-4 py-4 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-cyan-400 to-blue-500 flex items-center justify-center text-black font-bold text-sm">
              AR
            </div>
            <div>
              <h1 className="font-semibold text-lg">AptosRoom</h1>
              <p className="text-xs text-gray-400">Testnet</p>
            </div>
          </div>
          <WalletConnect />
        </div>
      </header>

      {/* Main Content */}
      <main className="max-w-7xl mx-auto px-4 py-6">
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
          {/* Left Sidebar - Keycard & Room List */}
          <div className="lg:col-span-4 space-y-6">
            <KeycardPanel />

            <RoomList
              onSelectRoom={setSelectedRoomId}
              selectedRoomId={selectedRoomId}
              refreshTrigger={refreshTrigger}
              optimisticRooms={optimisticRooms}
            />

            <CreateRoom onRoomCreated={handleRoomCreated} />
          </div>

          {/* Main Panel - Room Detail */}
          <div className="lg:col-span-8">
            {selectedRoomId ? (
              <RoomDetail
                roomId={selectedRoomId}
                onAction={handleRoomAction}
              />
            ) : (
              <div className="card text-center py-12">
                <div className="text-4xl mb-4">🏠</div>
                <h3 className="text-lg font-medium mb-2">Select a Room</h3>
                <p className="text-gray-400 text-sm">
                  Choose a room from the list to view details and actions,
                  <br />or create a new room to get started.
                </p>
              </div>
            )}
          </div>
        </div>
      </main>

      {/* Footer */}
      <footer className="border-t border-gray-800 mt-12">
        <div className="max-w-7xl mx-auto px-4 py-6 text-center text-sm text-gray-500">
          <p>AptosRoom Protocol Testing Frontend</p>
          <p className="mt-1">
            Contract: <code className="text-gray-400">{process.env.NEXT_PUBLIC_CONTRACT_ADDRESS?.slice(0, 10)}...</code>
          </p>
        </div>
      </footer>
    </div>
  );
}
