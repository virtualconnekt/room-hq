"use client";

import { useWallet } from "@aptos-labs/wallet-adapter-react";
import { useKeylessAuth } from "./KeylessAuthContext";

export function WalletConnect() {
    const { connect, disconnect, account, connected, wallets } = useWallet();
    const { keylessAccount, isKeylessUser, loginWithGoogle, logout, keylessAddress } = useKeylessAuth();

    const handleConnect = async () => {
        if (wallets && wallets.length > 0) {
            try {
                await connect(wallets[0].name);
            } catch (error) {
                console.error("Failed to connect wallet:", error);
            }
        }
    };

    const handleDisconnect = async () => {
        try {
            if (isKeylessUser) {
                logout();
            } else {
                await disconnect();
            }
        } catch (error) {
            console.error("Failed to disconnect:", error);
        }
    };

    const formatAddress = (address: string) => {
        return `${address.slice(0, 6)}...${address.slice(-4)}`;
    };

    // Connected via Keyless
    if (isKeylessUser && keylessAddress) {
        return (
            <div className="flex items-center gap-3">
                <span className="text-xs px-2 py-0.5 bg-blue-500/20 text-blue-400 rounded">Google</span>
                <span className="text-sm text-gray-400">
                    {formatAddress(keylessAddress)}
                </span>
                <button onClick={handleDisconnect} className="btn btn-secondary text-sm">
                    Logout
                </button>
            </div>
        );
    }

    // Connected via Wallet
    if (connected && account) {
        return (
            <div className="flex items-center gap-3">
                <span className="text-xs px-2 py-0.5 bg-purple-500/20 text-purple-400 rounded">Wallet</span>
                <span className="text-sm text-gray-400">
                    {formatAddress(account.address.toString())}
                </span>
                <button onClick={handleDisconnect} className="btn btn-secondary text-sm">
                    Disconnect
                </button>
            </div>
        );
    }

    // Not connected — show hybrid login
    return (
        <div className="flex items-center gap-2">
            <button
                onClick={loginWithGoogle}
                className="btn btn-primary flex items-center gap-2"
            >
                <svg viewBox="0 0 24 24" width="16" height="16" className="inline-block">
                    <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92a5.06 5.06 0 0 1-2.2 3.32v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.1z" />
                    <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" />
                    <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" />
                    <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" />
                </svg>
                Continue with Google
            </button>
            <button onClick={handleConnect} className="btn btn-secondary">
                Connect Wallet
            </button>
        </div>
    );
}
