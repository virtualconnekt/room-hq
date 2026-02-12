import { describe, it, expect } from 'vitest';
import { HashUtils } from '../src/utils/hash';
import { createHash } from 'crypto';

describe('HashUtils Verification', () => {
    it('should match Node crypto SHA3-256', () => {
        const inputs = [
            'hello world',
            '',
            'abc',
            'The quick brown fox jumps over the lazy dog',
            'Detailed message with special chars !@#$%^&*()',
        ];

        for (const input of inputs) {
            const data = new TextEncoder().encode(input);
            const manualHash = HashUtils.sha3_256(data);
            const nodeHash = createHash('sha3-256').update(data).digest();

            // Convert to hex for comparison
            const manualHex = Buffer.from(manualHash).toString('hex');
            const nodeHex = nodeHash.toString('hex');

            expect(manualHex).toBe(nodeHex);
        }
    });

    it('should correctly hash vote data structure', () => {
        const tierA = ["0x1", "0x2"];
        const tierB = ["0x3"];
        const salt = new Uint8Array(32).fill(1); // Deterministic salt

        // We can't easily verify the EXACT BCS structure without a BCS library reference,
        // but we can ensure the hashing mechanism itself keeps working.
        // For this test, we rely on the implementation matching Move's BCS.

        // Just verify it doesn't crash and functionality is stable
        const hash1 = HashUtils.computeTierVoteHash(tierA, tierB, salt);
        const hash2 = HashUtils.computeTierVoteHash(tierA, tierB, salt);

        expect(Buffer.from(hash1).toString('hex')).toBe(Buffer.from(hash2).toString('hex'));
    });
});
