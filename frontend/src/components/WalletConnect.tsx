"use client";

import { useWallet } from "@aptos-labs/wallet-adapter-react";

export function WalletConnect() {
    const { connect, disconnect, account, connected, wallets } = useWallet();

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
            await disconnect();
        } catch (error) {
            console.error("Failed to disconnect wallet:", error);
        }
    };

    const formatAddress = (address: string) => {
        return `${address.slice(0, 6)}...${address.slice(-4)}`;
    };

    if (connected && account) {
        return (
            <div className="flex items-center gap-3">
                <span className="text-sm text-gray-400">
                    {formatAddress(account.address.toString())}
                </span>
                <button
                    onClick={handleDisconnect}
                    className="btn btn-secondary text-sm"
                >
                    Disconnect
                </button>
            </div>
        );
    }

    return (
        <button onClick={handleConnect} className="btn btn-primary">
            Connect Wallet
        </button>
    );
}
