// Red para el navegador: misma interfaz `Net` que usan los scripts, pero firmando con la
// wallet del usuario (Phantom, Solflare…) o con una wallet desechable de devnet.
import {
  ComputeBudgetProgram,
  Connection,
  Keypair,
  PublicKey,
  SendTransactionError,
  SystemProgram,
  Transaction,
  TransactionInstruction,
} from "@solana/web3.js";
import type { Net } from "../../../scripts/lib/net";

export type TxSigner = {
  publicKey: PublicKey;
  signTransaction: (tx: Transaction) => Promise<Transaction>;
};

export class TxFailed extends Error {
  constructor(public label: string, message: string, public logs?: string[]) {
    super(message);
  }
}

export const CLUSTER = (import.meta.env.VITE_CLUSTER ?? "devnet") as "devnet" | "local";
export const RPC_URL = import.meta.env.VITE_RPC_URL ?? "https://api.devnet.solana.com";

export function explorerTx(sig: string) {
  return CLUSTER === "devnet" ? `https://explorer.solana.com/tx/${sig}?cluster=devnet` : "";
}
export function explorerAddress(a: PublicKey | string) {
  const s = typeof a === "string" ? a : a.toBase58();
  return CLUSTER === "devnet" ? `https://explorer.solana.com/address/${s}?cluster=devnet` : "";
}

function withBudget(ixs: TransactionInstruction[]) {
  const present = new Set(
    ixs.filter((ix) => ix.programId.equals(ComputeBudgetProgram.programId)).map((ix) => ix.data[0]),
  );
  const budget = [
    ComputeBudgetProgram.setComputeUnitLimit({ units: 1_200_000 }),
    ComputeBudgetProgram.setComputeUnitPrice({ microLamports: CLUSTER === "devnet" ? 20_000 : 0 }),
  ];
  return [...budget.filter((ix) => !present.has(ix.data[0])), ...ixs];
}

const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

export async function confirm(conn: Connection, sig: string, label: string) {
  const until = Date.now() + 90_000;
  while (Date.now() < until) {
    const { value } = await conn.getSignatureStatuses([sig]);
    const st = value[0];
    if (st?.err) throw new TxFailed(label, `Transaction failed: ${JSON.stringify(st.err)}`);
    if (st && (st.confirmationStatus === "confirmed" || st.confirmationStatus === "finalized")) return;
    await sleep(1200);
  }
  throw new TxFailed(label, "The network did not confirm the transaction in 90 seconds. Check your wallet history.");
}

export function makeBrowserNet(conn: Connection, signer: TxSigner): Net {
  const wallet = signer.publicKey;
  const send = async (label: string, ixs: TransactionInstruction[], signers: Keypair[]) => {
    const tx = new Transaction().add(...withBudget(ixs));
    tx.feePayer = wallet;
    tx.recentBlockhash = (await conn.getLatestBlockhash("confirmed")).blockhash;
    // Claves generadas por la app (config DBC, mint, NFTs de posición) firman aquí;
    // la wallet del usuario firma después.
    const extra = signers.filter((k) => k.secretKey && !k.publicKey.equals(wallet));
    if (extra.length) tx.partialSign(...extra);
    const signed = await signer.signTransaction(tx);
    let sig: string;
    try {
      sig = await conn.sendRawTransaction(signed.serialize(), { skipPreflight: false, preflightCommitment: "confirmed" });
    } catch (e: any) {
      const logs = e instanceof SendTransactionError ? (e.logs ?? undefined) : e?.logs;
      throw new TxFailed(label, String(e?.message ?? e), logs);
    }
    await confirm(conn, sig, label);
    return sig;
  };
  return {
    cluster: CLUSTER,
    conn,
    payer: { publicKey: wallet } as unknown as Keypair,
    send,
    explorer: explorerTx,
    advanceTime: (secs) => sleep(secs * 1000),
    fund: async (to, lamports) => {
      await send("Fund", [SystemProgram.transfer({ fromPubkey: wallet, toPubkey: to, lamports })], []);
    },
  };
}

// Mensajes legibles para los errores del programa y de Meteora.
const FRIENDLY: Record<string, string> = {
  ChallengeWindowOpen: "Holders still have time to object. Settle the tranche when the countdown ends.",
  ChallengeWindowClosed: "The objection window for this tranche has closed.",
  NotTeam: "Only the team that created this raise can propose a tranche.",
  InvalidState: "That action is not available at this stage of the raise.",
  ProposalActive: "A tranche is already waiting for holders. Settle it first.",
  NoActiveProposal: "There is no tranche waiting for holders right now.",
  VoteStillLocked: "Your tokens unlock once the tranche is settled.",
  InvalidGovernance: "Use at least 50% to the treasury, a window of 60 s or more and a quorum of 30% or less.",
  InvalidMilestones: "Tranches must add up to 100%, with 1 to 5 tranches.",
  NotPermitToDoThisAction: "Meteora refused the action: the curve has not graduated yet.",
  InsufficientFundsForRent: "Your wallet does not have enough SOL for this transaction.",
};

export function explainError(e: any): string {
  const text = `${e?.message ?? e}\n${(e?.logs ?? []).join("\n")}`;
  const code = text.match(/Error Code: (\w+)/)?.[1];
  if (code && FRIENDLY[code]) return FRIENDLY[code];
  if (/User rejected|rejected the request/i.test(text)) return "You cancelled the signature in your wallet.";
  if (/insufficient (funds|lamports)|Attempt to debit an account but found no record/i.test(text))
    return "Your wallet does not have enough SOL for this transaction.";
  if (/Insufficient Liquidity/i.test(text)) return "That buy is larger than what is left on the curve.";
  if (code) return `The program rejected the transaction (${code}).`;
  return String(e?.message ?? e).slice(0, 220);
}
