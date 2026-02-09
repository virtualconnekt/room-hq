/**
 * Simple SHA3-256 implementation using keccak
 * Note: For production, use a proper SHA3 library
 */
export class HashUtils {
  /**
   * Compute SHA3-256 hash of tier vote data
   * Must match Move's jury::compute_tier_commit_hash()
   * Format: BCS(tierA) || BCS(tierB) || salt
   * 
   * Move's BCS serialization for vector<address>:
   * - ULEB128 length prefix (for small arrays, this is just the length byte)
   * - Each address as 32 bytes
   */
  static computeTierVoteHash(
    tierA: string[],
    tierB: string[],
    salt: Uint8Array
  ): Uint8Array {
    // Serialize tierA as BCS vector<address>
    const tierABytes = this.serializeAddressVector(tierA);

    // Serialize tierB as BCS vector<address>
    const tierBBytes = this.serializeAddressVector(tierB);

    // Concatenate: tierA_bcs || tierB_bcs || salt
    const data = new Uint8Array(tierABytes.length + tierBBytes.length + salt.length);
    let offset = 0;

    data.set(tierABytes, offset);
    offset += tierABytes.length;

    data.set(tierBBytes, offset);
    offset += tierBBytes.length;

    data.set(salt, offset);

    return this.sha3_256(data);
  }

  /**
   * Serialize a vector of addresses in BCS format
   * Matches Move's bcs::to_bytes(&vector<address>)
   */
  static serializeAddressVector(addresses: string[]): Uint8Array {
    // ULEB128 encode the length (for lengths < 128, it's just the byte)
    const lengthBytes = this.encodeULEB128(addresses.length);

    // Each address is 32 bytes
    const addressesBytes = new Uint8Array(addresses.length * 32);
    for (let i = 0; i < addresses.length; i++) {
      const addrBytes = this.addressToBytes(addresses[i]);
      addressesBytes.set(addrBytes, i * 32);
    }

    // Combine length + addresses
    const result = new Uint8Array(lengthBytes.length + addressesBytes.length);
    result.set(lengthBytes, 0);
    result.set(addressesBytes, lengthBytes.length);

    return result;
  }

  /**
   * Convert address string to 32-byte array
   */
  static addressToBytes(address: string): Uint8Array {
    let cleanAddr = address.startsWith('0x') ? address.slice(2) : address;
    // Pad to 64 hex chars (32 bytes)
    cleanAddr = cleanAddr.padStart(64, '0');

    const bytes = new Uint8Array(32);
    for (let i = 0; i < 32; i++) {
      bytes[i] = parseInt(cleanAddr.substr(i * 2, 2), 16);
    }
    return bytes;
  }

  /**
   * Encode number as ULEB128 (unsigned LEB128)
   * For small numbers < 128, this is just the byte
   */
  static encodeULEB128(value: number): Uint8Array {
    const result: number[] = [];
    do {
      let byte = value & 0x7f;
      value >>>= 7;
      if (value !== 0) {
        byte |= 0x80;
      }
      result.push(byte);
    } while (value !== 0);
    return new Uint8Array(result);
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
