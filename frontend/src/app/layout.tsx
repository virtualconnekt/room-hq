import type { Metadata } from "next";
import "./globals.css";
import { WalletProvider } from "@/components/WalletProvider";
import { KeylessAuthProvider } from "@/components/KeylessAuthContext";

export const metadata: Metadata = {
  title: "AptosRoom Testnet",
  description: "Testing frontend for AptosRoom Protocol on Aptos Testnet",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>
        <WalletProvider>
          <KeylessAuthProvider>
            {children}
          </KeylessAuthProvider>
        </WalletProvider>
      </body>
    </html>
  );
}


