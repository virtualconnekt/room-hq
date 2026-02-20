/**
 * Rate-limited wrapper for Aptos API calls.
 * Uses a concurrency limiter (semaphore) instead of a serial queue.
 * Allows up to MAX_CONCURRENT requests in parallel, which is fast enough
 * for good UX but stays under testnet rate limits.
 */

const MAX_CONCURRENT = 3; // max parallel requests (testnet handles short bursts fine)
const MAX_RETRIES = 3;
const RETRY_BASE_DELAY_MS = 2000;

let activeCount = 0;
const waiting: Array<() => void> = [];

function acquireSlot(): Promise<void> {
    if (activeCount < MAX_CONCURRENT) {
        activeCount++;
        return Promise.resolve();
    }
    return new Promise<void>(resolve => {
        waiting.push(resolve);
    });
}

function releaseSlot(): void {
    if (waiting.length > 0) {
        const next = waiting.shift()!;
        next(); // hand the slot to the next waiter
    } else {
        activeCount--;
    }
}

/**
 * Execute an async function with concurrency limiting and retry.
 * Up to MAX_CONCURRENT calls run in parallel; extras wait for a slot.
 */
export async function enqueueRequest<T>(fn: () => Promise<T>): Promise<T> {
    await acquireSlot();
    try {
        return await retryWithBackoff(fn);
    } finally {
        releaseSlot();
    }
}

async function retryWithBackoff<T>(fn: () => Promise<T>): Promise<T> {
    for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {
        try {
            return await fn();
        } catch (err: any) {
            const msg = err?.message || String(err);
            const isRateLimit =
                msg.includes("429") ||
                msg.includes("Too Many") ||
                msg.includes("Failed to fetch") ||
                msg.includes("ERR_CONNECTION_CLOSED");
            if (isRateLimit && attempt < MAX_RETRIES) {
                console.warn(`[RateLimit] Retry ${attempt}/${MAX_RETRIES}, waiting ${RETRY_BASE_DELAY_MS * attempt}ms...`);
                await delay(RETRY_BASE_DELAY_MS * attempt);
            } else {
                throw err;
            }
        }
    }
    throw new Error("Max retries exceeded");
}

function delay(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
}
