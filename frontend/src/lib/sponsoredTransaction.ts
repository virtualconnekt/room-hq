import { GasStationClient } from "@aptos-labs/gas-station-client";
import { InputGenerateTransactionPayloadData, Network } from "@aptos-labs/ts-sdk";
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
