// Servidor JSON-RPC mínimo sobre LiteSVM (con los .so reales de DBC, DAMM v2 y OwnCurve).
// Implementa lo que usan web3.js, Anchor y el SDK de Meteora desde el navegador, más un
// método propio `owncurve_warp` para adelantar el reloj en los tests de la interfaz.
import { PublicKey, Transaction, VersionedTransaction } from "@solana/web3.js";
import bs58 from "bs58";
import http from "http";
import { makeNet } from "../../scripts/lib/net";

export async function startRpc(port = 8899) {
  process.env.CLUSTER = "local";
  const net = await makeNet();
  const svm = net.svm;
  const known = new Set<string>(); // LiteSVM no enumera cuentas: recordamos las que aparecen
  const statuses = new Map<string, { slot: number; err: any }>();
  const remember = (k: PublicKey | string) => known.add(typeof k === "string" ? k : k.toBase58());

  const slot = () => Number(svm.getClock().slot);
  const ctx = () => ({ slot: slot(), apiVersion: "3.1.14" });
  const acct = (pk: PublicKey) => {
    const a = svm.getAccount(pk);
    if (!a || (Number(a.lamports) === 0 && a.data.length === 0)) return null;
    return {
      data: [Buffer.from(a.data).toString("base64"), "base64"],
      executable: a.executable,
      lamports: Number(a.lamports),
      owner: new PublicKey(a.owner).toBase58(),
      rentEpoch: 0,
      space: a.data.length,
    };
  };
  const fakeSig = () => bs58.encode(Buffer.from(Array.from({ length: 64 }, () => Math.floor(Math.random() * 256))));
  const advance = () => {
    const c = svm.getClock();
    c.slot = c.slot + 1n;
    c.unixTimestamp = c.unixTimestamp + 1n;
    svm.setClock(c);
  };

  const methods: Record<string, (p: any[]) => any> = {
    getVersion: () => ({ "solana-core": "3.1.14", "feature-set": 0 }),
    getGenesisHash: () => "EtWTRABZaYq6iMfeYKouRu166VU2xqa1wcaWoxPkrZBG",
    getSlot: () => slot(),
    getBlockHeight: () => slot(),
    getEpochInfo: () => ({ absoluteSlot: slot(), blockHeight: slot(), epoch: 0, slotIndex: slot(), slotsInEpoch: 432000 }),
    getBlockTime: () => Number(svm.getClock().unixTimestamp),
    getLatestBlockhash: () => ({ context: ctx(), value: { blockhash: svm.latestBlockhash(), lastValidBlockHeight: slot() + 150 } }),
    getMinimumBalanceForRentExemption: ([n]) => Number(svm.minimumBalanceForRentExemption(BigInt(n))),
    getBalance: ([pk]) => ({ context: ctx(), value: Number(svm.getBalance(new PublicKey(pk)) ?? 0n) }),
    getAccountInfo: ([pk]) => {
      remember(pk);
      return { context: ctx(), value: acct(new PublicKey(pk)) };
    },
    getMultipleAccounts: ([pks]) => ({ context: ctx(), value: pks.map((k: string) => (remember(k), acct(new PublicKey(k)))) }),
    getTokenAccountBalance: ([pk]) => {
      const a = svm.getAccount(new PublicKey(pk));
      const amount = a && a.data.length >= 72 ? Buffer.from(a.data).readBigUInt64LE(64) : 0n;
      return { context: ctx(), value: { amount: amount.toString(), decimals: 9, uiAmount: Number(amount) / 1e9, uiAmountString: "" } };
    },
    getProgramAccounts: ([program, cfg]) => {
      const owner = new PublicKey(program);
      const out: any[] = [];
      for (const k of known) {
        const pk = new PublicKey(k);
        const a = svm.getAccount(pk);
        if (!a || !new PublicKey(a.owner).equals(owner)) continue;
        const data = Buffer.from(a.data);
        const ok = (cfg?.filters ?? []).every((f: any) => {
          if (f.dataSize !== undefined) return data.length === f.dataSize;
          if (f.memcmp) {
            const want = f.memcmp.encoding === "base64" ? Buffer.from(f.memcmp.bytes, "base64") : Buffer.from(bs58.decode(f.memcmp.bytes));
            return data.subarray(f.memcmp.offset, f.memcmp.offset + want.length).equals(want);
          }
          return true;
        });
        if (ok) out.push({ pubkey: k, account: acct(pk) });
      }
      return cfg?.withContext ? { context: ctx(), value: out } : out;
    },
    getSignatureStatuses: ([sigs]) => ({
      context: ctx(),
      value: sigs.map((s: string) => {
        const st = statuses.get(s);
        return st ? { slot: st.slot, confirmations: null, err: st.err, confirmationStatus: "confirmed", status: st.err ? { Err: st.err } : { Ok: null } } : null;
      }),
    }),
    requestAirdrop: ([pk, lamports]) => {
      remember(pk);
      svm.airdrop(new PublicKey(pk), BigInt(lamports));
      const sig = fakeSig();
      statuses.set(sig, { slot: slot(), err: null });
      return sig;
    },
    sendTransaction: ([b64]) => {
      const raw = Buffer.from(b64, "base64");
      let tx: Transaction | VersionedTransaction;
      let keys: PublicKey[];
      try {
        tx = Transaction.from(raw);
        keys = tx.compileMessage().accountKeys;
      } catch {
        tx = VersionedTransaction.deserialize(raw);
        keys = tx.message.staticAccountKeys;
      }
      keys.forEach(remember);
      const res: any = svm.sendTransaction(tx as any);
      svm.expireBlockhash();
      advance();
      if (res.constructor.name === "FailedTransactionMetadata" || typeof res.err === "function") {
        const logs: string[] = res.meta().logs();
        const err = { message: "Transaction simulation failed: " + res.err().toString(), logs };
        throw Object.assign(new Error(err.message), { rpc: { code: -32002, message: err.message, data: { err: res.err().toString(), logs, accounts: null, unitsConsumed: 0 } } });
      }
      const sig = bs58.encode((tx as any).signature ?? (tx as any).signatures[0]);
      statuses.set(sig, { slot: slot(), err: null });
      return sig;
    },
    simulateTransaction: ([b64, cfg]) => {
      const raw = Buffer.from(b64, cfg?.encoding === "base58" ? "base64" : "base64");
      let tx: Transaction | VersionedTransaction;
      try {
        tx = Transaction.from(raw);
        tx.compileMessage().accountKeys.forEach(remember);
      } catch {
        tx = VersionedTransaction.deserialize(raw);
        tx.message.staticAccountKeys.forEach(remember);
      }
      const res: any = svm.simulateTransaction(tx as any);
      const failed = res.constructor.name === "FailedTransactionMetadata" || typeof res.err === "function";
      const meta = failed ? res.meta() : res.meta();
      return {
        context: ctx(),
        value: {
          err: failed ? res.err().toString() : null,
          logs: meta.logs(),
          unitsConsumed: Number(meta.computeUnitsConsumed()),
          accounts: null,
          returnData: null,
        },
      };
    },
    // Solo para tests: adelanta el reloj de la cadena.
    owncurve_warp: ([secs]) => {
      const c = svm.getClock();
      c.unixTimestamp = c.unixTimestamp + BigInt(secs);
      c.slot = c.slot + BigInt(Math.ceil(secs * 2.5));
      svm.setClock(c);
      return Number(c.unixTimestamp);
    },
    owncurve_airdrop: ([pk, lamports]) => {
      remember(pk);
      svm.airdrop(new PublicKey(pk), BigInt(lamports));
      return true;
    },
  };

  const server = http.createServer((req, res) => {
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Headers", "*");
    res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
    if (req.method === "OPTIONS") return res.end();
    let body = "";
    req.on("data", (c) => (body += c));
    req.on("end", () => {
      const reqs = JSON.parse(body);
      const one = (r: any) => {
        const fn = methods[r.method];
        if (!fn) return { jsonrpc: "2.0", id: r.id, error: { code: -32601, message: `Method not found: ${r.method}` } };
        try {
          return { jsonrpc: "2.0", id: r.id, result: fn(r.params ?? []) };
        } catch (e: any) {
          return { jsonrpc: "2.0", id: r.id, error: e.rpc ?? { code: -32000, message: String(e.message ?? e) } };
        }
      };
      res.setHeader("Content-Type", "application/json");
      res.end(JSON.stringify(Array.isArray(reqs) ? reqs.map(one) : one(reqs)));
    });
  });
  await new Promise<void>((r) => server.listen(port, "127.0.0.1", () => r()));
  return { server, svm, net, url: `http://127.0.0.1:${port}` };
}

if (require.main === module) {
  startRpc().then(({ url }) => console.log(`LiteSVM RPC listo en ${url}`));
}
