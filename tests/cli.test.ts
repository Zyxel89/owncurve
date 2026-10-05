// Test del CLI (lo que usa la Agent Skill): cada comando es un proceso aparte que habla
// por JSON-RPC con un validador LiteSVM (el mismo servidor que el test E2E de la interfaz).
//
// Ejecutar:  npx tsx --test tests/cli.test.ts
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
const holder = Keypair.generate();
const dir = fs.mkdtempSync(path.join(os.tmpdir(), "owncurve-cli-"));
const wallet = (k: Keypair, name: string) => {
  const f = path.join(dir, `${name}.json`);
  fs.writeFileSync(f, JSON.stringify(Array.from(k.secretKey)));
  return f;
};

async function cli(who: Keypair, ...args: string[]) {
  const env = { ...process.env, CLUSTER: "devnet", RPC_URL: rpc.url, WALLET: wallet(who, who === team ? "team" : "holder") };
  try {
    const { stdout } = await run("npx", ["tsx", "scripts/cli.ts", ...args], { env, maxBuffer: 1 << 24 });
    return JSON.parse(stdout);
  } catch (e: any) {
    return JSON.parse(e.stdout || `{"ok":false,"error":${JSON.stringify(String(e.stderr || e.message))}}`);
  }
}
const yes = async (p: Promise<any>) => {
  const r = await p;
  assert.equal(r.ok, true, JSON.stringify(r));
  return r;
};
const warp = (secs: number) =>
  fetch(rpc.url, { method: "POST", body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "owncurve_warp", params: [secs] }) });

before(async () => {
  rpc = await startRpc(8898);
  rpc.svm.airdrop(team.publicKey, 10_000_000_000n);
  rpc.svm.airdrop(holder.publicKey, 2_000_000_000n);
});
after(() => rpc.server.close());

test("la Agent Skill puede llevar un raise de punta a punta solo con el CLI", { timeout: 600_000 }, async () => {
  // Escribir sin --yes solo simula
  const dry = await cli(team, "launch", "--name", "Agent Labs", "--symbol", "agnt");
  assert.equal(dry.dryRun, true, JSON.stringify(dry));
  assert.equal(dry.wouldSucceed, true, JSON.stringify(dry));
  assert.deepEqual(await cli(team, "list"), [], "la simulación no creó nada");

  const launched = await cli(team, "launch", "--name", "Agent Labs", "--symbol", "agnt", "--threshold", "0.5", "--yes");
  assert.equal(launched.ok, true, JSON.stringify(launched));
  const config = launched.config;
  let s = await cli(team, "show", config);
  assert.equal(s.state, "bonding");
  assert.ok(s.can.includes("buy"));
  assert.equal(s.rules.floorReservePct, 20);

  await yes(cli(team, "buy", config, "--sol", "0.3", "--yes"));
  await yes(cli(holder, "buy", config, "--sol", "0.002", "--yes"));
  await yes(cli(team, "buy", config, "--sol", "1", "--yes"));
  s = await cli(team, "show", config);
  assert.ok(s.curve.complete && s.can.includes("harvest"), JSON.stringify(s.curve));
  await yes(cli(team, "harvest", config, "--yes"));

  s = await cli(team, "show", config);
  assert.equal(s.guard.ghostTeam.armed, true, "harvest arma el guard");
  assert.equal(s.guard.bedrock.premiumPct, 30);

  // propose con evidencia: el hash queda en cadena y show lo devuelve
  const p = await cli(team, "propose", config, "--evidence", "https://example.com/m1", "--note", "M1 shipped", "--yes");
  assert.equal(p.ok, true, JSON.stringify(p));
  s = await cli(holder, "show", config);
  assert.equal(s.proposal.evidenceUri, "https://example.com/m1");
  assert.equal(s.proposal.evidenceSha256, p.evidenceSha256);
  assert.ok(s.can.includes("object"));

  // el holder objeta (no llega al quórum: el equipo tiene casi todo), se liquida el tramo
  await yes(cli(holder, "object", config, "--yes"));
  await warp(61);
  await yes(cli(holder, "settle", config, "--yes"));
  s = await cli(holder, "show", config);
  assert.equal(s.state, "funded", "la objeción no llegó al quórum");
  assert.equal(s.milestones[0].status, "released");
  assert.ok(s.can.includes("unlock"));
  await yes(cli(holder, "unlock", config, "--yes"));

  // errores del programa salen como JSON con el nombre del error
  const bad = await cli(holder, "propose", config, "--evidence", "https://example.com/x", "--yes");
  assert.equal(bad.ok, false);
  assert.match(bad.error, /NotTeam/);

  // piso: graduar, y defend-floor sin nada que defender lo explica
  await yes(cli(team, "migrate", config, "--yes"));
  s = await cli(team, "show", config);
  assert.ok(s.market && typeof s.market.pricePerMillionTokens === "number", JSON.stringify(s.market));
  assert.equal(s.market.belowBacking, false);
  assert.equal((await cli(team, "defend-floor", config, "--yes")).ok, false);
});
