// Red de trabajo: devnet real, o LiteSVM en memoria (para tests locales con los
// binarios reales de DBC). Ambos exponen lo mismo: `conn` (tipo Connection) y `send`.
import {
  Connection,
  Keypair,
  PublicKey,
  SystemProgram,
  Transaction,
  TransactionInstruction,
  ComputeBudgetProgram,
  sendAndConfirmTransaction,
} from "@solana/web3.js";
import fs from "fs";
import os from "os";
import path from "path";

export type Net = {
  cluster: "devnet" | "local";
  conn: Connection;
  payer: Keypair;
  send: (label: string, ixs: TransactionInstruction[], signers: Keypair[]) => Promise<string>;
  explorer: (sig: string) => string;
  /** local: adelanta el reloj del validador; devnet: espera de verdad. */
  advanceTime: (secs: number) => Promise<void>;
  /** local: airdrop; devnet: transferencia desde la wallet principal. */
  fund: (to: PublicKey, lamports: number) => Promise<void>;
  svm?: any;
};

export function loadKeypair(file: string): Keypair {
  const p = file.startsWith("~") ? path.join(os.homedir(), file.slice(1)) : file;
  return Keypair.fromSecretKey(Uint8Array.from(JSON.parse(fs.readFileSync(p, "utf8"))));
}

export async function makeNet(): Promise<Net> {
  const cluster = (process.env.CLUSTER ?? "devnet") as "devnet" | "local";
  if (cluster === "local") return makeLocal();

  const url = process.env.RPC_URL ?? "https://api.devnet.solana.com";
  const conn = new Connection(url, "confirmed");
  // RPC local sin websocket (el servidor de tests sobre LiteSVM): confirmar consultando.
  const pollOnly = /^http:\/\/(localhost|127\.0\.0\.1)/.test(url);
  const payer = loadKeypair(process.env.WALLET ?? "~/.config/solana/id.json");
  const send = async (label: string, ixs: TransactionInstruction[], signers: Keypair[]) => {
    const tx = new Transaction().add(
      ...withBudget(ixs, [
        ComputeBudgetProgram.setComputeUnitLimit({ units: 1_000_000 }),
        ComputeBudgetProgram.setComputeUnitPrice({ microLamports: 20_000 }),
      ]),
    );
    tx.feePayer = payer.publicKey;
    let lastErr: unknown;
    for (let attempt = 1; attempt <= 3; attempt++) {
      try {
        if (pollOnly) return await sendAndPoll(conn, tx, dedupe([payer, ...signers]));
        const sig = await sendAndConfirmTransaction(conn, tx, dedupe([payer, ...signers]), {
          commitment: "confirmed",
        });
        return sig;
      } catch (e: any) {
        lastErr = e;
        const logs: string[] | undefined = e?.logs ?? e?.transactionLogs;
        const msg = String(e?.message ?? e);
        // Errores del programa: no tiene sentido reintentar.
        if (logs || /custom program error|Simulation failed/i.test(msg)) {
          throw new TxError(label, msg, logs);
        }
        console.log(`   … ${label}: reintento ${attempt}/3 (${msg.slice(0, 80)})`);
        await new Promise((r) => setTimeout(r, 2500 * attempt));
      }
    }
    throw new TxError(label, String((lastErr as any)?.message ?? lastErr));
  };
  return {
    // un RPC local (LiteSVM detrás de JSON-RPC) usa la config local de DAMM v2
    cluster: pollOnly ? "local" : cluster,
    conn,
    payer,
    send,
    explorer: (sig) => `https://explorer.solana.com/tx/${sig}?cluster=devnet`,
    advanceTime: (secs) => new Promise((r) => setTimeout(r, (secs + 2) * 1000)),
    fund: async (to, lamports) => {
      await send("fondear", [SystemProgram.transfer({ fromPubkey: payer.publicKey, toPubkey: to, lamports })], []);
    },
  };
}

async function sendAndPoll(conn: Connection, tx: Transaction, signers: Keypair[]) {
  tx.recentBlockhash = (await conn.getLatestBlockhash("confirmed")).blockhash;
  tx.sign(...signers);
  const sig = await conn.sendRawTransaction(tx.serialize(), { preflightCommitment: "confirmed" });
  for (let i = 0; i < 60; i++) {
    const st = (await conn.getSignatureStatuses([sig])).value[0];
    if (st?.err) throw new Error(`Transaction ${sig} failed: ${JSON.stringify(st.err)}`);
    if (st) return sig;
    await new Promise((r) => setTimeout(r, 500));
  }
  throw new Error(`Transaction ${sig} not confirmed`);
}

export class TxError extends Error {
  constructor(public label: string, message: string, public logs?: string[]) {
    super(`${label}: ${message}`);
  }
}

// Añade nuestras instrucciones de ComputeBudget solo si la transacción (p. ej. del SDK
// de Meteora) no trae ya las suyas: Solana rechaza instrucciones de presupuesto duplicadas.
function withBudget(ixs: TransactionInstruction[], budget: TransactionInstruction[]) {
  const present = new Set(
    ixs.filter((ix) => ix.programId.equals(ComputeBudgetProgram.programId)).map((ix) => ix.data[0]),
  );
  return [...budget.filter((ix) => !present.has(ix.data[0])), ...ixs];
}

function dedupe(kps: Keypair[]): Keypair[] {
  const seen = new Set<string>();
  return kps.filter((k) => !seen.has(k.publicKey.toBase58()) && seen.add(k.publicKey.toBase58()));
}

// ---------------------------------------------------------------------------
// LiteSVM: validador en memoria con los .so reales de DBC y de OwnCurve.
// ---------------------------------------------------------------------------
async function makeLocal(): Promise<Net> {
  const { LiteSVM, FailedTransactionMetadata } = await import("litesvm");
  const svm = new LiteSVM();
  const so = (env: string, def: string) => process.env[env] ?? def;
  const DBC = new PublicKey("dbcij3LWUppWqq96dh6gJWwBifmcGfLSB5D4DuSMaqN");
  const DAMM_V2 = new PublicKey("cpamdpZCGKUy5JxQXB4dcpGPiikHawvSWAd6mEn1sGG");
  const idl = JSON.parse(fs.readFileSync("target/idl/owncurve.json", "utf8"));
  svm.addProgramFromFile(DBC, so("DBC_SO", "local/dynamic_bonding_curve.so"));
  if (fs.existsSync(so("DAMM_V2_SO", "local/damm_v2.so"))) {
    svm.addProgramFromFile(DAMM_V2, so("DAMM_V2_SO", "local/damm_v2.so"));
  }
  svm.addProgramFromFile(new PublicKey(idl.address), "target/deploy/owncurve.so");

  // Igual que en mainnet/devnet: la pool authority de DBC tiene lamports para "flash rent".
  const [poolAuthority] = PublicKey.findProgramAddressSync([Buffer.from("pool_authority")], DBC);
  svm.setAccount(poolAuthority, {
    lamports: 1_000_000_000,
    data: new Uint8Array(),
    owner: new PublicKey("11111111111111111111111111111111"),
    executable: false,
  });

  // Mint de SOL envuelto (wSOL), como en los tests de DBC: 9 decimales, inicializado.
  const nativeMint = new Uint8Array(82);
  nativeMint[44] = 9;
  nativeMint[45] = 1;
  svm.setAccount(new PublicKey("So11111111111111111111111111111111111111112"), {
    lamports: 1_390_379_946_687,
    data: nativeMint,
    owner: new PublicKey("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"),
    executable: false,
  });

  const payer = Keypair.generate();
  svm.airdrop(payer.publicKey, BigInt(100e9));
  const conn = new SvmConnection(svm) as unknown as Connection;

  const send = async (label: string, ixs: TransactionInstruction[], signers: Keypair[]) => {
    const tx = new Transaction().add(
      ...withBudget(ixs, [ComputeBudgetProgram.setComputeUnitLimit({ units: 1_400_000 })]),
    );
    tx.feePayer = payer.publicKey;
    tx.recentBlockhash = svm.latestBlockhash();
    tx.sign(...dedupe([payer, ...signers]));
    if (process.env.DEBUG) console.log(`   [svm] ${label}: ${tx.instructions.length} ix, ${tx.serialize().length} bytes`);
    const res = svm.sendTransaction(tx);
    svm.expireBlockhash();
    if (res instanceof FailedTransactionMetadata) {
      throw new TxError(label, res.err().toString(), res.meta().logs());
    }
    return Buffer.from(tx.signature!).toString("hex").slice(0, 16);
  };
  const advanceTime = async (secs: number) => {
    const c = svm.getClock();
    c.unixTimestamp = c.unixTimestamp + BigInt(secs);
    c.slot = c.slot + BigInt(Math.max(1, Math.ceil(secs * 2.5)));
    svm.setClock(c);
  };
  const fund = async (to: PublicKey, lamports: number) => {
    svm.airdrop(to, BigInt(lamports));
  };
  return { cluster: "local", conn, payer, send, explorer: (s) => `local:${s}`, advanceTime, fund, svm };
}

// Lo mínimo de Connection que usan Anchor y el SDK de DBC, respaldado por LiteSVM.
class SvmConnection {
  commitment = "confirmed";
  rpcEndpoint = "litesvm";
  constructor(private svm: any) {}
  private info(pk: PublicKey) {
    const a = this.svm.getAccount(pk);
    // LiteSVM devuelve las cuentas cerradas como vacías; una RPC real devuelve null.
    if (!a || (Number(a.lamports) === 0 && a.data.length === 0)) return null;
    return {
      data: Buffer.from(a.data),
      executable: a.executable,
      lamports: Number(a.lamports),
      owner: new PublicKey(a.owner),
      rentEpoch: 0,
    };
  }
  private ctx() {
    return { slot: Number(this.svm.getClock().slot) };
  }
  async getAccountInfo(pk: PublicKey) {
    return this.info(pk);
  }
  async getAccountInfoAndContext(pk: PublicKey) {
    return { context: this.ctx(), value: this.info(pk) };
  }
  async getMultipleAccountsInfo(pks: PublicKey[]) {
    return pks.map((p) => this.info(p));
  }
  async getMultipleAccountsInfoAndContext(pks: PublicKey[]) {
    return { context: this.ctx(), value: pks.map((p) => this.info(p)) };
  }
  async getSlot() {
    return Number(this.svm.getClock().slot);
  }
  async getBlockTime() {
    return Number(this.svm.getClock().unixTimestamp);
  }
  async getBalance(pk: PublicKey) {
    return Number(this.svm.getBalance(pk) ?? 0n);
  }
  async getLatestBlockhash() {
    return { blockhash: this.svm.latestBlockhash(), lastValidBlockHeight: 1_000_000_000 };
  }
  async getMinimumBalanceForRentExemption(n: number) {
    return Number(this.svm.minimumBalanceForRentExemption(BigInt(n)));
  }
  async getTokenAccountBalance(pk: PublicKey) {
    const a = this.info(pk);
    const amount = a ? Buffer.from(a.data).readBigUInt64LE(64) : 0n;
    return { context: this.ctx(), value: { amount: amount.toString(), decimals: 9, uiAmount: Number(amount) / 1e9 } };
  }
}

/** Carga el IDL compilado (solo Node). */
export function loadIdl(path = "target/idl/owncurve.json") {
  return JSON.parse(fs.readFileSync(path, "utf8"));
}
