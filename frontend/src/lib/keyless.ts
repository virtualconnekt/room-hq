"use client";

import { EphemeralKeyPair, KeylessAccount } from "@aptos-labs/ts-sdk";

// ============================================================
// EPHEMERAL KEY PAIR (generated before Google redirect)
// ============================================================

export const storeEphemeralKeyPair = (ekp: EphemeralKeyPair): void =>
    localStorage.setItem("@aptos/ekp", encodeEphemeralKeyPair(ekp));

export const getLocalEphemeralKeyPair = (): EphemeralKeyPair | undefined => {
    try {
        const encoded = localStorage.getItem("@aptos/ekp");
        return encoded ? decodeEphemeralKeyPair(encoded) : undefined;
    } catch (error) {
        console.warn("Failed to decode ephemeral key pair:", error);
        return undefined;
    }
};

export const encodeEphemeralKeyPair = (ekp: EphemeralKeyPair): string =>
    JSON.stringify(ekp, (_, e) => {
        if (typeof e === "bigint") return { __type: "bigint", value: e.toString() };
        if (e instanceof Uint8Array) return { __type: "Uint8Array", value: Array.from(e) };
        if (e instanceof EphemeralKeyPair) return { __type: "EphemeralKeyPair", data: e.bcsToBytes() };
        return e;
    });

export const decodeEphemeralKeyPair = (encodedEkp: string): EphemeralKeyPair =>
    JSON.parse(encodedEkp, (_, e) => {
        if (e && e.__type === "bigint") return BigInt(e.value);
        if (e && e.__type === "Uint8Array") return new Uint8Array(e.value);
        if (e && e.__type === "EphemeralKeyPair") return EphemeralKeyPair.fromBytes(e.data);
        return e;
    });

// ============================================================
// KEYLESS ACCOUNT (created after Google callback)
// ============================================================

export const storeKeylessAccount = (account: KeylessAccount): void =>
    localStorage.setItem("@aptos/account", encodeKeylessAccount(account));

export const getLocalKeylessAccount = (): KeylessAccount | undefined => {
    try {
        const encoded = localStorage.getItem("@aptos/account");
        return encoded ? decodeKeylessAccount(encoded) : undefined;
    } catch (error) {
        console.warn("Failed to decode keyless account:", error);
        return undefined;
    }
};

export const clearKeylessAccount = (): void => {
    localStorage.removeItem("@aptos/account");
    localStorage.removeItem("@aptos/ekp");
};

export const encodeKeylessAccount = (account: KeylessAccount): string =>
    JSON.stringify(account, (_, e) => {
        if (typeof e === "bigint") return { __type: "bigint", value: e.toString() };
        if (e instanceof Uint8Array) return { __type: "Uint8Array", value: Array.from(e) };
        if (e instanceof KeylessAccount) return { __type: "KeylessAccount", data: e.bcsToBytes() };
        return e;
    });

export const decodeKeylessAccount = (encodedAccount: string): KeylessAccount =>
    JSON.parse(encodedAccount, (_, e) => {
        if (e && e.__type === "bigint") return BigInt(e.value);
        if (e && e.__type === "Uint8Array") return new Uint8Array(e.value);
        if (e && e.__type === "KeylessAccount") return KeylessAccount.fromBytes(e.data);
        return e;
    });

// ============================================================
// GOOGLE LOGIN URL
// ============================================================

export function buildGoogleLoginUrl(ephemeralKeyPair: EphemeralKeyPair): string {
    const clientId = process.env.NEXT_PUBLIC_GOOGLE_CLIENT_ID!;
    const redirectUri = `${window.location.origin}/auth/callback`;
    const nonce = ephemeralKeyPair.nonce;

    return `https://accounts.google.com/o/oauth2/v2/auth?` +
        `response_type=id_token` +
        `&scope=openid+email+profile` +
        `&nonce=${nonce}` +
        `&redirect_uri=${encodeURIComponent(redirectUri)}` +
        `&client_id=${clientId}`;
}

export function parseJWTFromURL(url: string): string | null {
    const urlObject = new URL(url);
    const fragment = urlObject.hash.substring(1);
    const params = new URLSearchParams(fragment);
    return params.get("id_token");
}
