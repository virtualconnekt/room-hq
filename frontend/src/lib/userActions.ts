/**
 * Smart Dashboard - User Action Detection
 * Determines what actions a user needs to take based on their role and room state
 */

import { aptos, ROOM_STATES } from "./aptosroom";

const CONTRACT_ADDRESS = process.env.NEXT_PUBLIC_CONTRACT_ADDRESS!;

// Action types matching room states and user roles
export type ActionType =
  | "open_room"           // Client: INIT → OPEN
  | "score_submissions"   // Client: Score contributors in CLOSED state
  | "start_jury"          // Client: CLOSED → JURY_ACTIVE
  | "start_reveal"        // Client: JURY_ACTIVE → JURY_REVEAL
  | "commit_vote"         // Juror: Submit vote hash
  | "reveal_vote"         // Juror: Reveal vote
  | "finalize"            // Client: JURY_REVEAL → FINALIZED
  | "approve_settlement"  // Client: Approve in FINALIZED
  | "submit_work"         // Contributor: Submit in OPEN state
  | "claim_payout";       // Contributor/Juror: Claim after SETTLED

export type ActionPriority = "urgent" | "normal" | "low";

export interface UserAction {
  type: ActionType;
  roomId: number;
  roomState: number;
  category: string;
  deadline?: number;
  priority: ActionPriority;
  description: string;
  details?: {
    contributorCount?: number;
    jurySize?: number;
    hasCommitted?: boolean;
    hasRevealed?: boolean;
    currentScore?: number;
    requiredSlots?: { tierA: number; tierB: number };
  };
}

export interface RoomInfo {
  id: number;
  state: number;
  client: string;
  category: string;
  contributors: string[];
  juryPool: string[];
  deadlineSubmit?: number;
  deadlineJuryCommit?: number;
  deadlineJuryReveal?: number;
}

// View function helper
async function view(fnName: string, args: any[], moduleName = "room"): Promise<any[]> {
  const result = await aptos.view({
    payload: {
      function: `${CONTRACT_ADDRESS}::${moduleName}::${fnName}` as `${string}::${string}::${string}`,
      functionArguments: args,
    },
  });
  return result as any[];
}

/**
 * Fetch room details for action detection
 */
export async function fetchRoomInfo(roomId: number): Promise<RoomInfo | null> {
  try {
    const [stateRes, clientRes, categoryRes, contributorsRes, juryRes] = await Promise.all([
      view("get_state", [roomId.toString()]),
      view("get_client", [roomId.toString()]),
      view("get_category", [roomId.toString()]),
      view("get_contributor_list", [roomId.toString()]),
      view("get_jury_pool", [roomId.toString()]).catch(() => [[]]),
    ]);

    return {
      id: roomId,
      state: Number(stateRes[0]),
      client: String(clientRes[0]),
      category: String(categoryRes[0]),
      contributors: (contributorsRes[0] as string[]) || [],
      juryPool: (juryRes[0] as string[]) || [],
    };
  } catch (err) {
    console.error(`Failed to fetch room ${roomId}:`, err);
    return null;
  }
}

/**
 * Determine actions for a client (room creator)
 */
async function getClientActions(room: RoomInfo, userAddress: string): Promise<UserAction[]> {
  const actions: UserAction[] = [];

  if (room.client.toLowerCase() !== userAddress.toLowerCase()) {
    return actions;
  }

  switch (room.state) {
    case ROOM_STATES.INIT:
      actions.push({
        type: "open_room",
        roomId: room.id,
        roomState: room.state,
        category: room.category,
        priority: "normal",
        description: "Open room for submissions",
      });
      break;

    case ROOM_STATES.CLOSED:
      // Check if all contributors are scored
      const unscoredCount = await getUnscoredCount(room.id, room.contributors);
      if (unscoredCount > 0) {
        actions.push({
          type: "score_submissions",
          roomId: room.id,
          roomState: room.state,
          category: room.category,
          priority: "urgent",
          description: `Score ${unscoredCount} submission${unscoredCount > 1 ? "s" : ""}`,
          details: { contributorCount: room.contributors.length },
        });
      } else {
        actions.push({
          type: "start_jury",
          roomId: room.id,
          roomState: room.state,
          category: room.category,
          priority: "normal",
          description: "Start jury selection",
          details: { contributorCount: room.contributors.length },
        });
      }
      break;

    case ROOM_STATES.JURY_ACTIVE:
      actions.push({
        type: "start_reveal",
        roomId: room.id,
        roomState: room.state,
        category: room.category,
        priority: "normal",
        description: "Start reveal phase",
        details: { jurySize: room.juryPool.length },
      });
      break;

    case ROOM_STATES.JURY_REVEAL:
      actions.push({
        type: "finalize",
        roomId: room.id,
        roomState: room.state,
        category: room.category,
        priority: "normal",
        description: "Finalize scores",
        details: { jurySize: room.juryPool.length },
      });
      break;

    case ROOM_STATES.FINALIZED:
      const [approved] = await view("is_client_approved", [room.id.toString()]);
      if (!approved) {
        actions.push({
          type: "approve_settlement",
          roomId: room.id,
          roomState: room.state,
          category: room.category,
          priority: "urgent",
          description: "Approve settlement to release funds",
        });
      }
      break;
  }

  return actions;
}

/**
 * Determine actions for a juror
 */
async function getJurorActions(room: RoomInfo, userAddress: string): Promise<UserAction[]> {
  const actions: UserAction[] = [];

  const isJuror = room.juryPool.some(
    (j) => j.toLowerCase() === userAddress.toLowerCase()
  );

  if (!isJuror) {
    return actions;
  }

  switch (room.state) {
    case ROOM_STATES.JURY_ACTIVE:
      const [committed] = await view("has_committed_tier", [room.id.toString(), userAddress], "jury");
      if (!committed) {
        actions.push({
          type: "commit_vote",
          roomId: room.id,
          roomState: room.state,
          category: room.category,
          priority: "urgent",
          description: "Commit your tier vote",
          details: {
            contributorCount: room.contributors.length,
            hasCommitted: false,
          },
        });
      }
      break;

    case ROOM_STATES.JURY_REVEAL:
      const [hasCommitted] = await view("has_committed_tier", [room.id.toString(), userAddress], "jury");
      const [hasRevealed] = await view("has_revealed_tier", [room.id.toString(), userAddress], "jury");
      
      if (hasCommitted && !hasRevealed) {
        actions.push({
          type: "reveal_vote",
          roomId: room.id,
          roomState: room.state,
          category: room.category,
          priority: "urgent",
          description: "Reveal your vote",
          details: {
            hasCommitted: true,
            hasRevealed: false,
          },
        });
      }
      break;
  }

  return actions;
}

/**
 * Determine actions for a contributor
 */
async function getContributorActions(room: RoomInfo, userAddress: string): Promise<UserAction[]> {
  const actions: UserAction[] = [];

  const isContributor = room.contributors.some(
    (c) => c.toLowerCase() === userAddress.toLowerCase()
  );

  if (!isContributor) {
    return actions;
  }

  switch (room.state) {
    case ROOM_STATES.OPEN:
      const [hasSubmitted] = await view("has_submitted", [room.id.toString(), userAddress]);
      if (!hasSubmitted) {
        actions.push({
          type: "submit_work",
          roomId: room.id,
          roomState: room.state,
          category: room.category,
          priority: "normal",
          description: "Submit your work",
        });
      }
      break;

    case ROOM_STATES.SETTLED:
      const [claimed] = await view("has_contributor_claimed", [room.id.toString(), userAddress], "settlement")
        .catch(() => [false]);
      if (!claimed) {
        const [payout] = await view("get_contributor_payout", [room.id.toString(), userAddress], "settlement")
          .catch(() => [0]);
        if (Number(payout) > 0) {
          actions.push({
            type: "claim_payout",
            roomId: room.id,
            roomState: room.state,
            category: room.category,
            priority: "normal",
            description: `Claim your payout`,
            details: { currentScore: Number(payout) },
          });
        }
      }
      break;
  }

  return actions;
}

/**
 * Get count of unscored contributors
 */
async function getUnscoredCount(roomId: number, contributors: string[]): Promise<number> {
  let unscored = 0;
  for (const addr of contributors) {
    try {
      const [scoreOpt] = await view("get_client_score", [roomId.toString(), addr]);
      // scoreOpt is returned as object with vec field
      if (!scoreOpt || (scoreOpt as any).vec?.length === 0) {
        unscored++;
      }
    } catch {
      unscored++;
    }
  }
  return unscored;
}

/**
 * Main function: Get all actions for a user across all rooms
 */
export async function getUserActions(
  userAddress: string,
  roomIds: number[]
): Promise<UserAction[]> {
  const allActions: UserAction[] = [];

  // Fetch all room info in parallel
  const roomInfos = await Promise.all(
    roomIds.map((id) => fetchRoomInfo(id))
  );

  // Get actions for each room
  for (const room of roomInfos) {
    if (!room) continue;

    const [clientActions, jurorActions, contributorActions] = await Promise.all([
      getClientActions(room, userAddress),
      getJurorActions(room, userAddress),
      getContributorActions(room, userAddress),
    ]);

    allActions.push(...clientActions, ...jurorActions, ...contributorActions);
  }

  // Sort by priority
  const priorityOrder = { urgent: 0, normal: 1, low: 2 };
  return allActions.sort((a, b) => priorityOrder[a.priority] - priorityOrder[b.priority]);
}

/**
 * Get rooms grouped by relationship to user
 */
export async function getRoomRelationships(
  userAddress: string,
  roomIds: number[]
): Promise<{
  asClient: number[];
  asJuror: number[];
  asContributor: number[];
  watching: number[];
}> {
  const relationships = {
    asClient: [] as number[],
    asJuror: [] as number[],
    asContributor: [] as number[],
    watching: [] as number[],
  };

  for (const roomId of roomIds) {
    const room = await fetchRoomInfo(roomId);
    if (!room) continue;

    const addr = userAddress.toLowerCase();
    let hasRelationship = false;

    if (room.client.toLowerCase() === addr) {
      relationships.asClient.push(roomId);
      hasRelationship = true;
    }

    if (room.juryPool.some((j) => j.toLowerCase() === addr)) {
      relationships.asJuror.push(roomId);
      hasRelationship = true;
    }

    if (room.contributors.some((c) => c.toLowerCase() === addr)) {
      relationships.asContributor.push(roomId);
      hasRelationship = true;
    }

    if (!hasRelationship) {
      relationships.watching.push(roomId);
    }
  }

  return relationships;
}

/**
 * Format time remaining for deadlines
 */
export function formatTimeRemaining(deadline: number): string {
  const now = Math.floor(Date.now() / 1000);
  const remaining = deadline - now;

  if (remaining <= 0) return "Overdue";

  const hours = Math.floor(remaining / 3600);
  const days = Math.floor(hours / 24);

  if (days > 0) return `${days}d ${hours % 24}h remaining`;
  if (hours > 0) return `${hours}h remaining`;
  return `${Math.floor(remaining / 60)}m remaining`;
}

/**
 * Get priority badge color
 */
export function getPriorityColor(priority: ActionPriority): string {
  switch (priority) {
    case "urgent":
      return "bg-red-500/20 text-red-400 border-red-500/30";
    case "normal":
      return "bg-yellow-500/20 text-yellow-400 border-yellow-500/30";
    case "low":
      return "bg-gray-500/20 text-gray-400 border-gray-500/30";
  }
}

/**
 * Get action icon
 */
export function getActionIcon(type: ActionType): string {
  switch (type) {
    case "open_room":
      return "🚀";
    case "score_submissions":
      return "📝";
    case "start_jury":
      return "👥";
    case "start_reveal":
      return "🔓";
    case "commit_vote":
      return "🗳️";
    case "reveal_vote":
      return "👁️";
    case "finalize":
      return "✅";
    case "approve_settlement":
      return "💰";
    case "submit_work":
      return "📤";
    case "claim_payout":
      return "💸";
    default:
      return "📋";
  }
}
