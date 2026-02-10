"use client";

import { useWallet } from "@aptos-labs/wallet-adapter-react";
import { useState } from "react";
import { aptos, parseApt, formatApt, keycardClient } from "@/lib/aptosroom";

interface CreateRoomProps {
    onRoomCreated: () => void;
}

export function CreateRoom({ onRoomCreated }: CreateRoomProps) {
    const { account, connected, signAndSubmitTransaction } = useWallet();
    const [isOpen, setIsOpen] = useState(false);
    const [creating, setCreating] = useState(false);
    const [error, setError] = useState<string | null>(null);

    // Form state
    const [category, setCategory] = useState("design");
    const [taskDescription, setTaskDescription] = useState("");
    const [reward, setReward] = useState("1");
    const [submitDeadlineHours, setSubmitDeadlineHours] = useState("24");
    const [commitDeadlineHours, setCommitDeadlineHours] = useState("48");
    const [revealDeadlineHours, setRevealDeadlineHours] = useState("72");

    const handleCreate = async () => {
        if (!connected || !account) return;

        setCreating(true);
        setError(null);

        try {
            // Check if user has a keycard
            const hasKeycard = await keycardClient.hasKeycard(account.address.toString());
            if (!hasKeycard) {
                setError("You need a Keycard to create a room. Create one first.");
                return;
            }

            const contractAddress = process.env.NEXT_PUBLIC_CONTRACT_ADDRESS!;
            const now = Math.floor(Date.now() / 1000);

            // Parse reward to octas
            const rewardOctas = parseApt(reward);

            // Check balance
            try {
                const balance = await aptos.getAccountAPTAmount({
                    accountAddress: account.address,
                });

                // Need reward + a bit for gas (e.g. 0.01 APT)
                if (BigInt(balance) < rewardOctas + parseApt(0.01)) {
                    setError(`Insufficient balance. You need ${reward} APT + gas. Current: ${formatApt(balance)} APT`);
                    return;
                }
            } catch (e) {
                console.warn("Failed to check balance", e);
                // Continue anyway, maybe simulation will catch it or it works
            }

            // Calculate deadlines from now
            const submitDeadline = now + (parseInt(submitDeadlineHours) * 3600);
            const commitDeadline = now + (parseInt(commitDeadlineHours) * 3600);
            const revealDeadline = now + (parseInt(revealDeadlineHours) * 3600);

            // Create task hash from description
            const encoder = new TextEncoder();
            const taskHashBytes = encoder.encode(taskDescription || "Task Description");
            const taskHash = Array.from(taskHashBytes);

            const payload = {
                function: `${contractAddress}::room::create_room`,
                functionArguments: [
                    category,
                    taskHash,
                    rewardOctas.toString(),
                    submitDeadline.toString(),
                    commitDeadline.toString(),
                    revealDeadline.toString(),
                ],
            };

            // Simulate first to get exact error
            try {
                const transaction = await aptos.transaction.build.simple({
                    sender: account.address,
                    data: payload as any,
                });

                // Note: This simulation might fail if useWallet public key format doesn't match expected
                // but it's worth a try for debugging.
                // If account.publicKey is missing or weird, we skip simulation.
                if (account.publicKey) {
                    const [simResponse] = await aptos.transaction.simulate.simple({
                        signerPublicKey: account.publicKey as any, // Cast to avoid type issues with string vs PublicKey
                        transaction,
                    });

                    if (!simResponse.success) {
                        console.error("Simulation failed:", simResponse);
                        setError(`Simulation Failed: ${simResponse.vm_status}`);
                        return;
                    }
                }
            } catch (simErr) {
                console.warn("Simulation check failed (skipping):", simErr);
                // If our manual simulation fails (e.g. key format), we just proceed to try the wallet's submission
            }

            const response = await signAndSubmitTransaction({
                data: payload as any,
            });

            // Wait for transaction confirmation
            await aptos.waitForTransaction({ transactionHash: response.hash });

            // Reset form and close
            setIsOpen(false);
            setTaskDescription("");
            setReward("1");
            onRoomCreated();
        } catch (err) {
            console.error("Error creating room:", err);
            setError("Failed to create room. Make sure you have enough APT for the escrow.");
        } finally {
            setCreating(false);
        }
    };

    if (!isOpen) {
        return (
            <button
                onClick={() => setIsOpen(true)}
                disabled={!connected}
                className="btn btn-primary w-full"
            >
                + Create Room
            </button>
        );
    }

    return (
        <div className="card mt-4">
            <div className="flex items-center justify-between mb-4">
                <h3 className="font-semibold">Create Room</h3>
                <button
                    onClick={() => setIsOpen(false)}
                    className="text-gray-400 hover:text-white"
                >
                    ✕
                </button>
            </div>

            {error && (
                <p className="text-red-400 text-sm mb-3">{error}</p>
            )}

            <div className="space-y-4">
                <div>
                    <label className="block text-sm text-gray-400 mb-1">Category</label>
                    <select
                        value={category}
                        onChange={(e) => setCategory(e.target.value)}
                        className="w-full"
                    >
                        <option value="design">Design</option>
                        <option value="development">Development</option>
                        <option value="writing">Writing</option>
                        <option value="marketing">Marketing</option>
                        <option value="other">Other</option>
                    </select>
                </div>

                <div>
                    <label className="block text-sm text-gray-400 mb-1">Task Description</label>
                    <textarea
                        value={taskDescription}
                        onChange={(e) => setTaskDescription(e.target.value)}
                        placeholder="Describe the task..."
                        rows={2}
                        className="w-full"
                    />
                </div>

                <div>
                    <label className="block text-sm text-gray-400 mb-1">Reward (APT)</label>
                    <input
                        type="number"
                        value={reward}
                        onChange={(e) => setReward(e.target.value)}
                        min="0.01"
                        step="0.1"
                        placeholder="1.0"
                    />
                    <p className="text-xs text-gray-500 mt-1">This amount will be escrowed</p>
                </div>

                <div className="grid grid-cols-3 gap-2">
                    <div>
                        <label className="block text-xs text-gray-400 mb-1">Submit (hrs)</label>
                        <input
                            type="number"
                            value={submitDeadlineHours}
                            onChange={(e) => setSubmitDeadlineHours(e.target.value)}
                            min="1"
                        />
                    </div>
                    <div>
                        <label className="block text-xs text-gray-400 mb-1">Commit (hrs)</label>
                        <input
                            type="number"
                            value={commitDeadlineHours}
                            onChange={(e) => setCommitDeadlineHours(e.target.value)}
                            min="1"
                        />
                    </div>
                    <div>
                        <label className="block text-xs text-gray-400 mb-1">Reveal (hrs)</label>
                        <input
                            type="number"
                            value={revealDeadlineHours}
                            onChange={(e) => setRevealDeadlineHours(e.target.value)}
                            min="1"
                        />
                    </div>
                </div>

                <div className="flex gap-2">
                    <button
                        onClick={() => setIsOpen(false)}
                        className="btn btn-secondary flex-1"
                    >
                        Cancel
                    </button>
                    <button
                        onClick={handleCreate}
                        disabled={creating || !connected}
                        className="btn btn-primary flex-1"
                    >
                        {creating ? "Creating..." : "Create & Escrow"}
                    </button>
                </div>
            </div>
        </div>
    );
}
