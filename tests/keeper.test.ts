// Test del keeper: hace solo los trabajos sin permiso (harvest, settle, observe, abandono) en un
// validador local expuesto por JSON-RPC, como lo haría en GitHub Actions contra devnet.
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
const keeper = Keypair.generate();
const dir = fs.mkdtempSync(path.join(os.tmpdir(), "owncurve-keeper-"));
const file = (k: Keypair, n: string) => {
  const f = path.join(dir, `${n}.json`);
  fs.writeFileSync(f, JSON.stringify(Array.from(k.secretKey)));
  return f;
};

before(async () => {
  rpc = await startRpc(8892);
  rpc.svm.airdrop(team.publicKey, 10_000_000_000n);
  rpc.svm.airdrop(keeper.publicKey, 1_000_000_000n);
});
after(() => rpc.server.close());

const warp = (secs: number) =>
  fetch(rpc.url, { method: "POST", body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "owncurve_warp", params: [secs] }) });

test("el keeper cosecha, liquida tramos, registra el TWAP y activa el interruptor de equipo fantasma", { timeout: 600_000 }, async () => {
  const teamEnv = { ...process.env, CLUSTER: "devnet", RPC_URL: rpc.url, WALLET: file(team, "team") };
  const cli = async (...a: string[]) => JSON.parse((await run("npx", ["tsx", "scripts/cli.ts", ...a], { env: teamEnv })).stdout);
  const kdir = fs.mkdtempSync(path.join(dir, "k-"));
  const keep = async () => {
    await run("npx", ["tsx", path.resolve("scripts/keeper.ts")], {
      env: { ...process.env, CLUSTER: "devnet", RPC_URL: rpc.url, WALLET: file(keeper, "keeper"), KEEPER_OUT: path.join(kdir, "keeper-run.json") },
    });
    return JSON.parse(fs.readFileSync(path.join(kdir, "keeper-run.json"), "utf8")).actions as { action: string; ok: boolean }[];
  };
  const did = (acts: { action: string; ok: boolean }[], name: string) => acts.some((x) => x.action === name && x.ok);

  const { config } = await cli("launch", "--name", "Keeper Test", "--symbol", "kt", "--inactivity", "300", "--twap", "120", "--yes");
  await cli("buy", config, "--spend", "1", "--yes");
  assert.ok(did(await keep(), "harvest"), "harvest");
  assert.equal((await cli("show", config)).state, "funded");

  await cli("propose", config, "--evidence", "https://example.com/m1", "--yes");
  await warp(61);
  assert.ok(did(await keep(), "settle"), "settle");
  assert.equal((await cli("show", config)).milestones[0].status, "released");

  await cli("migrate", config, "--yes");
  assert.ok(did(await keep(), "observe"), "observe");
  await warp(301);
  const acts = await keep();
  assert.ok(did(acts, "declare_abandoned"), JSON.stringify(acts));
  assert.equal((await cli("show", config)).state, "liquidating");
});
