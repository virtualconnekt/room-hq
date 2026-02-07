/**
 * Hash utilities for commit-reveal
 * Using Web Crypto API for SHA3-256 equivalent
 */

/**
 * Simple SHA3-256 implementation using keccak
 * Note: For production, use a proper SHA3 library
 */
export class HashUtils {
  /**
   * Compute SHA3-256 hash of tier vote data
   * Format: sort(tierA) || sort(tierB) || salt
   */
  static computeTierVoteHash(
    tierA: string[],
    tierB: string[],
    salt: Uint8Array
  ): Uint8Array {
    // Sort addresses for deterministic ordering
    const sortedTierA = [...tierA].sort();
    const sortedTierB = [...tierB].sort();

    // Create preimage: tierA addresses + tierB addresses + salt
    const encoder = new TextEncoder();
    const tierABytes = encoder.encode(sortedTierA.join(','));
    const tierBBytes = encoder.encode(sortedTierB.join(','));

    // Concatenate all parts
    const preimage = new Uint8Array(tierABytes.length + 1 + tierBBytes.length + 1 + salt.length);
    let offset = 0;
    
    preimage.set(tierABytes, offset);
    offset += tierABytes.length;
    preimage[offset++] = 0x00; // separator
    
    preimage.set(tierBBytes, offset);
    offset += tierBBytes.length;
    preimage[offset++] = 0x00; // separator
    
    preimage.set(salt, offset);

    return this.sha3_256(preimage);
  }

  /**
   * Compute SHA3-256 hash of standard vote
   * Format: participant || score || salt
   */
  static computeVoteHash(
    participant: string,
    score: number,
    salt: Uint8Array
  ): Uint8Array {
    const encoder = new TextEncoder();
    const participantBytes = encoder.encode(participant);
    const scoreBytes = new Uint8Array([score]);

    const preimage = new Uint8Array(participantBytes.length + 1 + scoreBytes.length + salt.length);
    let offset = 0;

    preimage.set(participantBytes, offset);
    offset += participantBytes.length;
    preimage[offset++] = 0x00;
    preimage.set(scoreBytes, offset);
    offset += scoreBytes.length;
    preimage.set(salt, offset);

    return this.sha3_256(preimage);
  }

  /**
   * SHA3-256 hash function
   * Simplified Keccak implementation matching Move's sha3_256
   */
  static sha3_256(data: Uint8Array): Uint8Array {
    // Keccak-256 implementation
    // Rate = 1088 bits (136 bytes), Capacity = 512 bits
    const RATE = 136;
    const OUTPUT_LEN = 32;

    // Keccak round constants
    const RC = [
      0x0000000000000001n, 0x0000000000008082n, 0x800000000000808an, 0x8000000080008000n,
      0x000000000000808bn, 0x0000000080000001n, 0x8000000080008081n, 0x8000000000008009n,
      0x000000000000008an, 0x0000000000000088n, 0x0000000080008009n, 0x000000008000000an,
      0x000000008000808bn, 0x800000000000008bn, 0x8000000000008089n, 0x8000000000008003n,
      0x8000000000008002n, 0x8000000000000080n, 0x000000000000800an, 0x800000008000000an,
      0x8000000080008081n, 0x8000000000008080n, 0x0000000080000001n, 0x8000000080008008n,
    ];

    // Rotation offsets
    const ROTATIONS = [
      [0, 36, 3, 41, 18],
      [1, 44, 10, 45, 2],
      [62, 6, 43, 15, 61],
      [28, 55, 25, 21, 56],
      [27, 20, 39, 8, 14],
    ];

    // Initialize state (5x5 array of 64-bit integers)
    const state: bigint[][] = Array.from({ length: 5 }, () => Array(5).fill(0n));

    // Pad message (SHA3 padding: append 0x06, then zeros, then 0x80)
    const padLen = RATE - (data.length % RATE);
    const padded = new Uint8Array(data.length + padLen);
    padded.set(data);
    padded[data.length] = 0x06;
    padded[padded.length - 1] |= 0x80;

    // Absorb phase
    for (let i = 0; i < padded.length; i += RATE) {
      // XOR block into state
      for (let j = 0; j < RATE / 8; j++) {
        const x = j % 5;
        const y = Math.floor(j / 5);
        let lane = 0n;
        for (let k = 0; k < 8; k++) {
          lane |= BigInt(padded[i + j * 8 + k]) << BigInt(k * 8);
        }
        state[x][y] ^= lane;
      }

      // Keccak-f[1600] permutation (24 rounds)
      for (let round = 0; round < 24; round++) {
        // θ step
        const C: bigint[] = [];
        for (let x = 0; x < 5; x++) {
          C[x] = state[x][0] ^ state[x][1] ^ state[x][2] ^ state[x][3] ^ state[x][4];
        }
        const D: bigint[] = [];
        for (let x = 0; x < 5; x++) {
          D[x] = C[(x + 4) % 5] ^ this.rotl64(C[(x + 1) % 5], 1n);
        }
        for (let x = 0; x < 5; x++) {
          for (let y = 0; y < 5; y++) {
            state[x][y] ^= D[x];
          }
        }

        // ρ and π steps
        const B: bigint[][] = Array.from({ length: 5 }, () => Array(5).fill(0n));
        for (let x = 0; x < 5; x++) {
          for (let y = 0; y < 5; y++) {
            B[y][(2 * x + 3 * y) % 5] = this.rotl64(state[x][y], BigInt(ROTATIONS[x][y]));
          }
        }

        // χ step
        for (let x = 0; x < 5; x++) {
          for (let y = 0; y < 5; y++) {
            state[x][y] = B[x][y] ^ (~B[(x + 1) % 5][y] & B[(x + 2) % 5][y]);
          }
        }

        // ι step
        state[0][0] ^= RC[round];
      }
    }

    // Squeeze phase (only need 256 bits = 32 bytes)
    const output = new Uint8Array(OUTPUT_LEN);
    let outIdx = 0;
    outer: for (let y = 0; y < 5; y++) {
      for (let x = 0; x < 5; x++) {
        for (let k = 0; k < 8; k++) {
          if (outIdx >= OUTPUT_LEN) break outer;
          output[outIdx++] = Number((state[x][y] >> BigInt(k * 8)) & 0xffn);
        }
      }
    }

    return output;
  }

  /**
   * 64-bit left rotation
   */
  private static rotl64(x: bigint, n: bigint): bigint {
    const mask = 0xffffffffffffffffn;
    n = n % 64n;
    return ((x << n) | (x >> (64n - n))) & mask;
  }

  /**
   * Compare two hashes for equality
   */
  static hashesEqual(a: Uint8Array, b: Uint8Array): boolean {
    if (a.length !== b.length) return false;
    let result = 0;
    for (let i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result === 0;
  }

  /**
   * Convert bytes to hex string
   */
  static bytesToHex(bytes: Uint8Array): string {
    return Array.from(bytes)
      .map((b) => b.toString(16).padStart(2, '0'))
      .join('');
  }

  /**
   * Convert hex string to bytes
   */
  static hexToBytes(hex: string): Uint8Array {
    const cleanHex = hex.startsWith('0x') ? hex.slice(2) : hex;
    const bytes = new Uint8Array(cleanHex.length / 2);
    for (let i = 0; i < bytes.length; i++) {
      bytes[i] = parseInt(cleanHex.substr(i * 2, 2), 16);
    }
    return bytes;
  }
}
