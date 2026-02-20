"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { jwtDecode } from "jwt-decode";
import { aptos } from "@/lib/aptosroom";
import {
    getLocalEphemeralKeyPair,
    parseJWTFromURL,
    storeKeylessAccount,
} from "@/lib/keyless";

export default function AuthCallbackPage() {
    const router = useRouter();
    const [status, setStatus] = useState("Processing Google login...");
    const [error, setError] = useState<string | null>(null);

    useEffect(() => {
        const handleCallback = async () => {
            try {
                // 1. Extract JWT from URL fragment
                const jwt = parseJWTFromURL(window.location.href);
                if (!jwt) {
                    throw new Error("No id_token found in callback URL");
                }
                setStatus("Token received, verifying...");

                // 2. Decode JWT and extract nonce
                const payload = jwtDecode<{ nonce: string; email?: string }>(jwt);
                const jwtNonce = payload.nonce;
                console.log("[Keyless Callback] JWT decoded, email:", payload.email);

                // 3. Get stored EphemeralKeyPair and validate
                const ekp = getLocalEphemeralKeyPair();
                if (!ekp) {
                    throw new Error("Ephemeral key pair not found. Please try logging in again.");
                }
                if (ekp.nonce !== jwtNonce) {
                    throw new Error("Nonce mismatch. Please try logging in again.");
                }
                if (ekp.isExpired()) {
                    throw new Error("Session expired. Please try logging in again.");
                }

                setStatus("Creating your Keyless account...");

                // 4. Derive the Keyless account (with retry for rate limiting)
                let keylessAccount;
                const MAX_RETRIES = 3;
                for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {
                    try {
                        keylessAccount = await aptos.deriveKeylessAccount({
                            jwt,
                            ephemeralKeyPair: ekp,
                        });
                        break; // success
                    } catch (deriveErr: any) {
                        const isRateLimit = deriveErr?.message?.includes("Failed to fetch") ||
                            deriveErr?.message?.includes("429") ||
                            deriveErr?.message?.includes("keyless configuration");
                        if (isRateLimit && attempt < MAX_RETRIES) {
                            setStatus(`Rate limited, retrying (${attempt}/${MAX_RETRIES})...`);
                            await new Promise(r => setTimeout(r, 2000 * attempt));
                        } else {
                            throw deriveErr;
                        }
                    }
                }
                if (!keylessAccount) throw new Error("Failed to derive account after retries");

                console.log("[Keyless Callback] Account derived:", keylessAccount.accountAddress.toString());
                setStatus("Account created! Redirecting...");

                // 5. Store the account
                storeKeylessAccount(keylessAccount);

                // 6. Notify the parent context if available
                if ((window as any).__setKeylessAccount) {
                    (window as any).__setKeylessAccount(keylessAccount);
                }

                // 7. Redirect to dashboard
                setTimeout(() => router.push("/"), 500);
            } catch (err: any) {
                console.error("[Keyless Callback] Error:", err);
                setError(err.message || "Failed to process Google login");
            }
        };

        handleCallback();
    }, [router]);

    return (
        <div className="min-h-screen flex items-center justify-center bg-gray-950">
            <div className="card max-w-md w-full text-center">
                {error ? (
                    <>
                        <div className="text-4xl mb-4">❌</div>
                        <h2 className="text-xl font-bold text-red-400 mb-2">Login Failed</h2>
                        <p className="text-gray-400 text-sm mb-4">{error}</p>
                        <button
                            onClick={() => router.push("/")}
                            className="btn btn-primary"
                        >
                            Back to Dashboard
                        </button>
                    </>
                ) : (
                    <>
                        <div className="text-4xl mb-4 animate-spin">⏳</div>
                        <h2 className="text-xl font-bold text-white mb-2">{status}</h2>
                        <p className="text-gray-500 text-sm">Please wait...</p>
                    </>
                )}
            </div>
        </div>
    );
}
