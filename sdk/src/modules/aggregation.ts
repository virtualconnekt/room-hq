/**
 * Aggregation Module Client
 * Handles vote aggregation and final score processing
 */
import {
    Aptos,
    Account,
    type PendingTransactionResponse,
    type InputGenerateTransactionPayloadData,
} from '@aptos-labs/ts-sdk';

export class AggregationClient {
    constructor(
        private readonly aptos: Aptos,
        private readonly moduleAddress: string
    ) { }

    /**
     * Aggregate tier votes for a room
     * Must be called after Reveal phase and before Finalize
     */
    async aggregateTierVotes(
        account: Account,
        roomId: number
    ): Promise<PendingTransactionResponse> {
        const payload: InputGenerateTransactionPayloadData = {
            function: `${this.moduleAddress}::aggregation::aggregate_tier_votes`,
            functionArguments: [BigInt(roomId)],
        };

        const tx = await this.aptos.transaction.build.simple({
            sender: account.accountAddress,
            data: payload,
        });

        const signedTx = await this.aptos.transaction.sign({
            signer: account,
            transaction: tx,
        });

        return await this.aptos.transaction.submit.simple({
            senderAuthenticator: signedTx,
            transaction: tx,
        });
    }

    /**
     * Process final scores using tier-based jury scores
     * Must be called after client scores are set and before Settlement
     */
    async processTierFinalScores(
        account: Account,
        roomId: number
    ): Promise<PendingTransactionResponse> {
        const payload: InputGenerateTransactionPayloadData = {
            function: `${this.moduleAddress}::aggregation::process_tier_final_scores`,
            functionArguments: [BigInt(roomId)],
        };

        const tx = await this.aptos.transaction.build.simple({
            sender: account.accountAddress,
            data: payload,
        });

        const signedTx = await this.aptos.transaction.sign({
            signer: account,
            transaction: tx,
        });

        return await this.aptos.transaction.submit.simple({
            senderAuthenticator: signedTx,
            transaction: tx,
        });
    }

    // ============================================================
    // VIEW FUNCTIONS
    // ============================================================

    /**
     * Check if tiers have been computed
     */
    async areTiersComputed(roomId: number): Promise<boolean> {
        const result = await this.aptos.view({
            payload: {
                function: `${this.moduleAddress}::aggregation::are_tiers_computed`,
                functionArguments: [BigInt(roomId)],
            },
        });
        return result[0] as boolean;
    }

    /**
     * Get calculated jury score for a room
     */
    async getJuryScore(roomId: number): Promise<number> {
        const result = await this.aptos.view({
            payload: {
                function: `${this.moduleAddress}::aggregation::get_jury_score`,
                functionArguments: [BigInt(roomId)],
            },
        });
        return Number(result[0]);
    }

    /**
     * Get final score for a contributor
     */
    async getFinalScore(roomId: number, contributor: string): Promise<number> {
        const result = await this.aptos.view({
            payload: {
                function: `${this.moduleAddress}::aggregation::get_final_score`,
                functionArguments: [BigInt(roomId), contributor],
            },
        });
        return Number(result[0]);
    }

    /**
     * Get contributor tier (1=A, 2=B, 3=C)
     */
    async getContributorTier(roomId: number, contributor: string): Promise<number> {
        const result = await this.aptos.view({
            payload: {
                function: `${this.moduleAddress}::aggregation::get_contributor_tier`,
                functionArguments: [BigInt(roomId), contributor],
            },
        });
        return Number(result[0]);
    }
}
