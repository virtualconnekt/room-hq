import { NextResponse } from 'next/server';
import prisma from '@/lib/prisma';

// Force dynamic so it doesn't cache at build time
export const dynamic = 'force-dynamic';

export async function GET() {
    try {
        const rooms = await prisma.room.findMany({
            orderBy: { createdAt: 'desc' },
        });

        // We serialize the BigInt fields to strings to avoid errors during JSON.stringify
        const serializedRooms = rooms.map((room: any) => ({
            ...room,
            roomId: room.roomId.toString(),
            taskReward: room.taskReward.toString(),
            createdAt: room.createdAt.toString(),
        }));

        return NextResponse.json({ rooms: serializedRooms });
    } catch (error) {
        console.error('Error fetching rooms:', error);
        return NextResponse.json({ error: 'Failed to fetch rooms' }, { status: 500 });
    }
}
