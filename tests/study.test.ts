// Test del estudio de mainnet contra un validador local: dos lanzamientos de OwnCurve (tarifa a
// una PDA, LP bloqueado, sin autoridad de emisión) deben contar como "OwnCurve-grade".
import { Keypair } from "@solana/web3.js";
import { execFile } from "child_process";
import fs from "fs";
import os from "os";
import path from "path";
import assert from "node:assert/strict";
import { after, before, test } from "node:test";
import { promisify } from "util";
import { startRpc } from "./e2e/rpc-server";

const run = promisify(execFile);
let rpc: Awaited<ReturnType<typeof startRpc>>;
const team = Keypair.generate();
const dir = fs.mkdtempSync(path.join(os.tmpdir(), "owncurve-study-"));
const wallet = path.join(dir, "team.json");

before(async () => {
  rpc = await startRpc(8895);
  rpc.svm.airdrop(team.publicKey, 10_000_000_000n);
  fs.writeFileSync(wallet, JSON.stringify(Array.from(team.secretKey)));
});
after(() => rpc.server.close());

test("el estudio lee configs y lanzamientos de DBC y clasifica sus garantías", { timeout: 300_000 }, async () => {
  const env = { ...process.env, CLUSTER: "devnet", RPC_URL: rpc.url, WALLET: wallet };
  for (const name of ["Study One", "Study Two"])
    await run("npx", ["tsx", "scripts/cli.ts", "launch", "--name", name, "--symbol", "st", "--yes"], { env });
  const out = path.join(dir, "out");
  fs.mkdirSync(out);
  await run("npx", ["tsx", path.resolve("scripts/study.ts")], { env: { ...process.env, MAINNET_RPC: rpc.url }, cwd: out });
  const r = JSON.parse(fs.readFileSync(path.join(out, "docs/mainnet-study.json"), "utf8"));
  assert.equal(r.configs, 2);
  assert.equal(r.launches, 2);
  assert.equal(r.metrics.feeToProgram.launches, 2, "la tarifa va a la PDA de la tesorería");
  assert.equal(r.metrics.feeToWallet.launches, 0);
  assert.equal(r.metrics.ownCurveGrade.launchesPct, 100);
  assert.equal(r.metrics.quoteSol.launches, 2);
  assert.match(fs.readFileSync(path.join(out, "docs/MAINNET-STUDY.md"), "utf8"), /2 configs · 2 launches/);
});
