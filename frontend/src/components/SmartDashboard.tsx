"use client";

import { useState, useEffect, useCallback } from "react";
import { useWallet } from "@aptos-labs/wallet-adapter-react";
import {
  UserAction,
  getUserActions,
  getRoomRelationships,
  getPriorityColor,
  getActionIcon,
  ActionPriority,
} from "@/lib/userActions";
import { STATE_LABELS } from "@/lib/aptosroom";
import { useKeylessAuth } from "./KeylessAuthContext";

interface SmartDashboardProps {
  roomIds: number[];
  onRoomSelect: (roomId: number) => void;
  onRefresh: () => void;
}

export function SmartDashboard({ roomIds, onRoomSelect, onRefresh }: SmartDashboardProps) {
  const { account, connected } = useWallet();
  const { keylessAccount, isKeylessUser, keylessAddress } = useKeylessAuth();

  const [actions, setActions] = useState<UserAction[]>([]);
  const [relationships, setRelationships] = useState<{
    asClient: number[];
    asJuror: number[];
    asContributor: number[];
    watching: number[];
  }>({ asClient: [], asJuror: [], asContributor: [], watching: [] });
  const [loading, setLoading] = useState(true);
  const [activeTab, setActiveTab] = useState<"actions" | "watching" | "completed">("actions");

  const activeAddress = isKeylessUser
    ? keylessAddress
    : connected && account
    ? account.address.toString()
    : null;

  const isAuthenticated = isKeylessUser || (connected && !!account);

  // Fetch user's actions
  const fetchDashboardData = useCallback(async () => {
    if (!activeAddress || roomIds.length === 0) {
      setLoading(false);
      return;
    }

    setLoading(true);
    try {
      const [userActions, roomRels] = await Promise.all([
        getUserActions(activeAddress, roomIds),
        getRoomRelationships(activeAddress, roomIds),
      ]);
      setActions(userActions);
      setRelationships(roomRels);
    } catch (err) {
      console.error("Failed to fetch dashboard data:", err);
    } finally {
      setLoading(false);
    }
  }, [activeAddress, roomIds]);

  useEffect(() => {
    fetchDashboardData();
  }, [fetchDashboardData]);

  // Group actions by priority
  const urgentActions = actions.filter((a) => a.priority === "urgent");
  const normalActions = actions.filter((a) => a.priority === "normal");

  // Completed rooms (settled)
  const completedRoomIds = roomIds.filter(async (id) => {
    // We'd need to check state, but for simplicity show watching as completed filter
    return false;
  });

  if (!isAuthenticated) {
    return (
      <div className="card">
        <h2 className="text-lg font-semibold mb-4">📋 Your Tasks</h2>
        <p className="text-gray-400 text-sm">
          Connect wallet or sign in to see your tasks
        </p>
      </div>
    );
  }

  if (loading) {
    return (
      <div className="card">
        <h2 className="text-lg font-semibold mb-4">📋 Your Tasks</h2>
        <div className="animate-pulse space-y-3">
          <div className="h-16 bg-gray-800 rounded-lg" />
          <div className="h-16 bg-gray-800 rounded-lg" />
        </div>
      </div>
    );
  }

  const totalActionCount = actions.length;
  const urgentCount = urgentActions.length;

  return (
    <div className="space-y-4">
      {/* Header with counts */}
      <div className="card">
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-lg font-semibold">📋 Your Tasks</h2>
          <button
            onClick={fetchDashboardData}
            className="text-xs text-gray-400 hover:text-white transition-colors"
          >
            ↻ Refresh
          </button>
        </div>

        {/* Quick stats */}
        <div className="grid grid-cols-3 gap-3 mb-4">
          <div className="bg-gray-800/50 rounded-lg p-3 text-center">
            <div className="text-2xl font-bold text-white">{totalActionCount}</div>
            <div className="text-xs text-gray-400">Pending</div>
          </div>
          <div className="bg-gray-800/50 rounded-lg p-3 text-center">
            <div className="text-2xl font-bold text-red-400">{urgentCount}</div>
            <div className="text-xs text-gray-400">Urgent</div>
          </div>
          <div className="bg-gray-800/50 rounded-lg p-3 text-center">
            <div className="text-2xl font-bold text-gray-400">
              {relationships.asClient.length +
                relationships.asJuror.length +
                relationships.asContributor.length}
            </div>
            <div className="text-xs text-gray-400">Involved</div>
          </div>
        </div>

        {/* Tabs */}
        <div className="flex gap-1 bg-gray-800/30 rounded-lg p-1">
          <button
            onClick={() => setActiveTab("actions")}
            className={`flex-1 py-2 px-3 rounded-md text-sm font-medium transition-colors ${
              activeTab === "actions"
                ? "bg-cyan-500/20 text-cyan-400"
                : "text-gray-400 hover:text-white"
            }`}
          >
            ⚡ Actions {totalActionCount > 0 && `(${totalActionCount})`}
          </button>
          <button
            onClick={() => setActiveTab("watching")}
            className={`flex-1 py-2 px-3 rounded-md text-sm font-medium transition-colors ${
              activeTab === "watching"
                ? "bg-cyan-500/20 text-cyan-400"
                : "text-gray-400 hover:text-white"
            }`}
          >
            👁️ Watching
          </button>
          <button
            onClick={() => setActiveTab("completed")}
            className={`flex-1 py-2 px-3 rounded-md text-sm font-medium transition-colors ${
              activeTab === "completed"
                ? "bg-cyan-500/20 text-cyan-400"
                : "text-gray-400 hover:text-white"
            }`}
          >
            ✓ Done
          </button>
        </div>
      </div>

      {/* Tab content */}
      {activeTab === "actions" && (
        <div className="space-y-3">
          {actions.length === 0 ? (
            <div className="card text-center py-8">
              <div className="text-4xl mb-2">🎉</div>
              <p className="text-gray-400">All caught up!</p>
              <p className="text-gray-500 text-sm">No pending actions</p>
            </div>
          ) : (
            <>
              {/* Urgent actions */}
              {urgentActions.length > 0 && (
                <div className="space-y-2">
                  <h3 className="text-sm font-medium text-red-400 flex items-center gap-2">
                    <span className="w-2 h-2 bg-red-500 rounded-full animate-pulse" />
                    Action Required ({urgentActions.length})
                  </h3>
                  {urgentActions.map((action) => (
                    <ActionCard
                      key={`${action.roomId}-${action.type}`}
                      action={action}
                      onClick={() => onRoomSelect(action.roomId)}
                    />
                  ))}
                </div>
              )}

              {/* Normal actions */}
              {normalActions.length > 0 && (
                <div className="space-y-2">
                  <h3 className="text-sm font-medium text-gray-400 flex items-center gap-2">
                    Pending ({normalActions.length})
                  </h3>
                  {normalActions.map((action) => (
                    <ActionCard
                      key={`${action.roomId}-${action.type}`}
                      action={action}
                      onClick={() => onRoomSelect(action.roomId)}
                    />
                  ))}
                </div>
              )}
            </>
          )}
        </div>
      )}

      {activeTab === "watching" && (
        <div className="space-y-2">
          {relationships.asClient.length === 0 &&
          relationships.asJuror.length === 0 &&
          relationships.asContributor.length === 0 ? (
            <div className="card text-center py-8">
              <p className="text-gray-400">You&apos;re not involved in any rooms yet</p>
            </div>
          ) : (
            <>
              {relationships.asClient.length > 0 && (
                <div>
                  <h3 className="text-sm font-medium text-purple-400 mb-2">
                    👔 As Client ({relationships.asClient.length})
                  </h3>
                  <div className="space-y-1">
                    {relationships.asClient.map((roomId) => (
                      <RoomRow
                        key={roomId}
                        roomId={roomId}
                        onClick={() => onRoomSelect(roomId)}
                      />
                    ))}
                  </div>
                </div>
              )}

              {relationships.asJuror.length > 0 && (
                <div>
                  <h3 className="text-sm font-medium text-blue-400 mb-2">
                    ⚖️ As Juror ({relationships.asJuror.length})
                  </h3>
                  <div className="space-y-1">
                    {relationships.asJuror.map((roomId) => (
                      <RoomRow
                        key={roomId}
                        roomId={roomId}
                        onClick={() => onRoomSelect(roomId)}
                      />
                    ))}
                  </div>
                </div>
              )}

              {relationships.asContributor.length > 0 && (
                <div>
                  <h3 className="text-sm font-medium text-green-400 mb-2">
                    🎨 As Contributor ({relationships.asContributor.length})
                  </h3>
                  <div className="space-y-1">
                    {relationships.asContributor.map((roomId) => (
                      <RoomRow
                        key={roomId}
                        roomId={roomId}
                        onClick={() => onRoomSelect(roomId)}
                      />
                    ))}
                  </div>
                </div>
              )}
            </>
          )}
        </div>
      )}

      {activeTab === "completed" && (
        <div className="card text-center py-8">
          <div className="text-4xl mb-2">🏆</div>
          <p className="text-gray-400">Completed tasks will appear here</p>
          <p className="text-gray-500 text-sm">Rooms you&apos;ve finished participating in</p>
        </div>
      )}
    </div>
  );
}

// Individual action card
function ActionCard({ action, onClick }: { action: UserAction; onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      className={`w-full text-left card hover:border-gray-600 transition-all group ${getPriorityBorderClass(
        action.priority
      )}`}
    >
      <div className="flex items-start gap-3">
        <div className="text-2xl">{getActionIcon(action.type)}</div>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2">
            <span className="font-medium text-white group-hover:text-cyan-400 transition-colors">
              {action.description}
            </span>
            <PriorityBadge priority={action.priority} />
          </div>
          <div className="flex items-center gap-2 mt-1 text-xs text-gray-500">
            <span>Room #{action.roomId}</span>
            <span>•</span>
            <span>{action.category}</span>
            {action.details?.contributorCount && (
              <>
                <span>•</span>
                <span>{action.details.contributorCount} submissions</span>
              </>
            )}
          </div>
        </div>
        <div className="text-gray-500 group-hover:text-cyan-400 transition-colors">
          →
        </div>
      </div>
    </button>
  );
}

// Simple room row for watching tab
function RoomRow({ roomId, onClick }: { roomId: number; onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      className="w-full flex items-center justify-between p-2 rounded-lg bg-gray-800/30 hover:bg-gray-800/50 transition-colors text-left group"
    >
      <span className="text-sm text-gray-300 group-hover:text-white transition-colors">
        Room #{roomId}
      </span>
      <span className="text-gray-500 group-hover:text-cyan-400 transition-colors text-xs">
        View →
      </span>
    </button>
  );
}

// Priority badge
function PriorityBadge({ priority }: { priority: ActionPriority }) {
  return (
    <span
      className={`text-xs px-2 py-0.5 rounded-full border ${getPriorityColor(priority)}`}
    >
      {priority}
    </span>
  );
}

// Get border class for priority
function getPriorityBorderClass(priority: ActionPriority): string {
  switch (priority) {
    case "urgent":
      return "border-red-500/30 bg-red-500/5";
    case "normal":
      return "border-yellow-500/30 bg-yellow-500/5";
    case "low":
      return "border-gray-700";
  }
}
