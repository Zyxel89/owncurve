// Test del escáner de lanzamientos: un raise de OwnCurve saca A+ (buscado por mint, por pool y
// por config) y una config DBC "de rug" (tarifa a una wallet, LP desbloqueado, parte al creador) suspende.
import { Connection, Keypair, PublicKey, Transaction } from "@solana/web3.js";
import { execFile } from "child_process";
import fs from "fs";
import os from "os";
import path from "path";
import assert from "node:assert/strict";
import { after, before, test } from "node:test";
import { promisify } from "util";
import { loadIdl } from "../scripts/lib/net";
import { DEFAULT_PARAMS, OwnCurve } from "../scripts/lib/owncurve";
import { scanLaunch } from "../scripts/lib/scan";
import { startRpc } from "./e2e/rpc-server";

const run = promisify(execFile);
let rpc: Awaited<ReturnType<typeof startRpc>>;
const team = Keypair.generate();
const dir = fs.mkdtempSync(path.join(os.tmpdir(), "owncurve-scan-"));
const wallet = path.join(dir, "team.json");

before(async () => {
  rpc = await startRpc(8894);
  rpc.svm.airdrop(team.publicKey, 10_000_000_000n);
  fs.writeFileSync(wallet, JSON.stringify(Array.from(team.secretKey)));
});
after(() => rpc.server.close());

test("el escáner califica lanzamientos de Meteora DBC por mint, pool o config", { timeout: 300_000 }, async () => {
  const env = { ...process.env, CLUSTER: "devnet", RPC_URL: rpc.url, WALLET: wallet };
  const { stdout } = await run("npx", ["tsx", "scripts/cli.ts", "launch", "--name", "Scan Me", "--symbol", "scan", "--yes"], { env });
  const config = JSON.parse(stdout).config;
  const conn = new Connection(rpc.url, "confirmed");
  const idl = loadIdl() as any;
  const pid = new PublicKey(idl.address);
  const byConfig = await scanLaunch(conn, config, pid);
  assert.equal(byConfig.grade, "A+", JSON.stringify(byConfig.checks));
  assert.ok(byConfig.ownCurve);
  const byPool = await scanLaunch(conn, byConfig.pool ?? (await scanLaunch(conn, config, pid)).config, pid);
  const show = JSON.parse((await run("npx", ["tsx", "scripts/cli.ts", "show", config], { env })).stdout);
  const byMint = await scanLaunch(conn, show.baseMint, pid);
  assert.equal(byMint.grade, "A+");
  assert.equal(byMint.config, config);
  assert.ok(byMint.pool && byMint.curve && byMint.curve.threshold === 0.5);
  assert.equal(byPool.config, config);

  // config "de rug" creada directamente en DBC (bind_pool de OwnCurve la rechazaría)
  const net: any = {
    cluster: "local",
    conn,
    payer: team,
    explorer: (s: string) => s,
    advanceTime: async () => {},
    fund: async () => {},
    send: async (_l: string, ixs: any[], signers: any[]) => {
      const tx = new Transaction().add(...ixs);
      tx.feePayer = team.publicKey;
      tx.recentBlockhash = (await conn.getLatestBlockhash()).blockhash;
      tx.sign(team, ...signers.filter((k: Keypair) => !k.publicKey.equals(team.publicKey)));
      const sig = await conn.sendRawTransaction(tx.serialize());
      return sig;
    },
  };
  const oc = new OwnCurve(net, idl);
  const rug = await oc.createRaise({ ...DEFAULT_PARAMS, guard: null, feeClaimer: team.publicKey, creatorMigrationFeePct: 50, creatorUnlockedLpPct: 50 });
  const bad = await scanLaunch(conn, rug.configKp.publicKey.toBase58(), pid);
  assert.equal(bad.ownCurve, false);
  assert.ok(["D", "F"].includes(bad.grade), `nota ${bad.grade}`);
  assert.equal(bad.checks.find((c) => c.id === "fee")!.ok, false, "tarifa a una wallet");
  assert.equal(bad.checks.find((c) => c.id === "lp")!.ok, false, "LP desbloqueado");
  assert.equal(bad.checks.find((c) => c.id === "creator-fee")!.ok, false);
});
