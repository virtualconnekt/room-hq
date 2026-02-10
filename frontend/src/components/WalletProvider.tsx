"use client";

import { AptosWalletAdapterProvider } from "@aptos-labs/wallet-adapter-react";
import { PetraWallet } from "petra-plugin-wallet-adapter";
import { Network } from "@aptos-labs/ts-sdk";
import { ReactNode } from "react";

const wallets = [new PetraWallet()];

interface WalletProviderProps {
    children: ReactNode;
}

import { transactionSubmitter } from "@/lib/aptosroom";

export function WalletProvider({ children }: WalletProviderProps) {
    return (
        <AptosWalletAdapterProvider
            plugins={wallets}
            autoConnect={true}
            dappConfig={{
                network: Network.TESTNET,
                aptosApiKey: undefined,
                transactionSubmitter: transactionSubmitter as any,
            } as any}
            onError={(error) => {
                console.error("Wallet error:", error);
            }}
        >
            {children}
        </AptosWalletAdapterProvider>
    );
}
