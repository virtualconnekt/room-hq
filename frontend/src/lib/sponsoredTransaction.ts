import { GasStationClient } from "@aptos-labs/gas-station-client";
import { InputGenerateTransactionPayloadData, Network, KeylessAccount } from "@aptos-labs/ts-sdk";
import { aptos } from "@/lib/aptosroom";

const NETWORK = (process.env.NEXT_PUBLIC_APTOS_NETWORK || "testnet") as
  | "testnet"
  | "mainnet"
  | "devnet";
const GAS_STATION_API_KEY = process.env.NEXT_PUBLIC_GAS_STATION_API_KEY;

const gasStationClient = GAS_STATION_API_KEY
  ? new GasStationClient({
    network:
      NETWORK === "testnet"
        ? Network.TESTNET
        : NETWORK === "mainnet"
          ? Network.MAINNET
          : Network.DEVNET,
    apiKey: GAS_STATION_API_KEY,
  })
  : undefined;

interface SubmitSponsoredTransactionArgs {
  accountAddress: string;
  data: InputGenerateTransactionPayloadData;
  signTransaction: (transaction: any) => Promise<any>;
  signAndSubmitTransaction: (transaction: { data: InputGenerateTransactionPayloadData }) => Promise<any>;
}

export async function submitSponsoredTransaction({
  accountAddress,
  data,
  signTransaction,
  signAndSubmitTransaction,
}: SubmitSponsoredTransactionArgs): Promise<{ hash: string }> {
  // Fallback when sponsorship is not configured.
  if (!gasStationClient) {
    const response = await signAndSubmitTransaction({ data });
    return { hash: response.hash };
  }

  console.log("Sponsored txn: building transaction...", { sender: accountAddress, data });
  const transaction = await aptos.transaction.build.simple({
    sender: accountAddress,
    withFeePayer: true,
    data,
    options: {
      expireTimestamp: Math.floor(Date.now() / 1000) + 120, // 2 minutes from now
    },
  });
  const response = await signTransaction({ transactionOrPayload: transaction });
  const senderAuthenticator = response.authenticator;

  const submitResponse = await gasStationClient.signAndSubmitTransaction({
    transaction: transaction as any,
    senderAuthenticator: senderAuthenticator as any,
  });

  return { hash: submitResponse.transactionHash };
}

/**
 * Submit a sponsored transaction signed by a KeylessAccount.
 * Uses Gas Station as fee payer when available, falls back to direct signing.
 */
export async function submitKeylessSponsoredTransaction({
  keylessAccount,
  data,
}: {
  keylessAccount: KeylessAccount;
  data: InputGenerateTransactionPayloadData;
}): Promise<{ hash: string }> {
  if (!gasStationClient) {
    // No Gas Station: sign and submit directly (user pays gas)
    const transaction = await aptos.transaction.build.simple({
      sender: keylessAccount.accountAddress,
      data,
    });
    const committed = await aptos.signAndSubmitTransaction({ signer: keylessAccount, transaction });
    return { hash: committed.hash };
  }

  // Gas Station path: build with fee payer, sign with keyless, submit through Gas Station
  console.log("Keyless sponsored txn: building...", { sender: keylessAccount.accountAddress.toString() });
  const transaction = await aptos.transaction.build.simple({
    sender: keylessAccount.accountAddress,
    withFeePayer: true,
    data,
    options: {
      expireTimestamp: Math.floor(Date.now() / 1000) + 120,
    },
  });

  const senderAuthenticator = aptos.transaction.sign({ signer: keylessAccount, transaction });

  const submitResponse = await gasStationClient.signAndSubmitTransaction({
    transaction: transaction as any,
    senderAuthenticator: senderAuthenticator as any,
  });

  return { hash: submitResponse.transactionHash };
}

/**
 * Submit a transaction directly without Gas Station sponsorship.
 * Use for functions not on the Gas Station allowlist (e.g. #[randomness] entry functions).
 * The user pays gas for this transaction.
 */
export async function submitDirectTransaction({
  data,
  signAndSubmitTransaction,
}: {
  data: InputGenerateTransactionPayloadData;
  signAndSubmitTransaction: (transaction: { data: InputGenerateTransactionPayloadData }) => Promise<any>;
}): Promise<{ hash: string }> {
  const response = await signAndSubmitTransaction({ data });
  return { hash: response.hash };
}
