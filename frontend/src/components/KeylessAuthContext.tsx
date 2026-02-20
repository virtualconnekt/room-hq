"use client";

import { createContext, useContext, useState, useEffect, ReactNode, useCallback } from "react";
import { KeylessAccount, EphemeralKeyPair } from "@aptos-labs/ts-sdk";
import { aptos } from "@/lib/aptosroom";
import {
    storeEphemeralKeyPair,
    getLocalKeylessAccount,
    storeKeylessAccount,
    clearKeylessAccount,
    buildGoogleLoginUrl,
} from "@/lib/keyless";

interface KeylessAuthContextType {
    keylessAccount: KeylessAccount | null;
    isKeylessUser: boolean;
    isLoading: boolean;
    loginWithGoogle: () => void;
    logout: () => void;
    keylessAddress: string | null;
}

const KeylessAuthContext = createContext<KeylessAuthContextType>({
    keylessAccount: null,
    isKeylessUser: false,
    isLoading: true,
    loginWithGoogle: () => { },
    logout: () => { },
    keylessAddress: null,
});

export function useKeylessAuth() {
    return useContext(KeylessAuthContext);
}

export function KeylessAuthProvider({ children }: { children: ReactNode }) {
    const [keylessAccount, setKeylessAccount] = useState<KeylessAccount | null>(null);
    const [isLoading, setIsLoading] = useState(true);

    // Load stored keyless account on mount — deferred so components mount
    // unauthenticated first, matching the Petra wallet async connection pattern.
    // This prevents all fetch calls from firing simultaneously on page load.
    useEffect(() => {
        const timer = setTimeout(() => {
            try {
                const stored = getLocalKeylessAccount();
                if (stored) {
                    console.log("[Keyless] Restored account from localStorage:", stored.accountAddress.toString());
                    setKeylessAccount(stored);
                }
            } catch (err) {
                console.warn("[Keyless] Failed to restore account:", err);
                clearKeylessAccount();
            }
            setIsLoading(false);
        }, 100); // Small delay so components mount first without auth
        return () => clearTimeout(timer);
    }, []);

    const loginWithGoogle = useCallback(() => {
        const ekp = EphemeralKeyPair.generate();
        storeEphemeralKeyPair(ekp);
        const loginUrl = buildGoogleLoginUrl(ekp);
        console.log("[Keyless] Redirecting to Google OAuth...");
        window.location.href = loginUrl;
    }, []);

    const logout = useCallback(() => {
        clearKeylessAccount();
        setKeylessAccount(null);
        console.log("[Keyless] Logged out");
    }, []);

    // Called from the callback page to set the account
    const setAccount = useCallback((account: KeylessAccount) => {
        storeKeylessAccount(account);
        setKeylessAccount(account);
    }, []);

    // Expose setAccount on window for the callback page to use
    useEffect(() => {
        (window as any).__setKeylessAccount = setAccount;
        return () => {
            delete (window as any).__setKeylessAccount;
        };
    }, [setAccount]);

    const value: KeylessAuthContextType = {
        keylessAccount,
        isKeylessUser: keylessAccount !== null,
        isLoading,
        loginWithGoogle,
        logout,
        keylessAddress: keylessAccount?.accountAddress.toString() ?? null,
    };

    return (
        <KeylessAuthContext.Provider value={value}>
            {children}
        </KeylessAuthContext.Provider>
    );
}
