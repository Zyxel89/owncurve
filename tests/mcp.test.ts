// Test del servidor MCP: un cliente MCP real (SDK oficial) lanza `scripts/mcp.ts` por stdio y
// lo usa contra un validador LiteSVM expuesto por JSON-RPC.
//
// Ejecutar:  npx tsx --test tests/mcp.test.ts
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { Keypair } from "@solana/web3.js";
import assert from "node:assert/strict";
import fs from "fs";
import os from "os";
import path from "path";
import { after, before, test } from "node:test";
import { startRpc } from "./e2e/rpc-server";

let rpc: Awaited<ReturnType<typeof startRpc>>;
let client: Client;
const team = Keypair.generate();

before(async () => {
  rpc = await startRpc(8896);
  rpc.svm.airdrop(team.publicKey, 10_000_000_000n);
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "owncurve-mcp-"));
  const wallet = path.join(dir, "team.json");
  fs.writeFileSync(wallet, JSON.stringify(Array.from(team.secretKey)));
  client = new Client({ name: "owncurve-test", version: "1.0.0" });
  await client.connect(
    new StdioClientTransport({
      command: "npx",
      args: ["tsx", "scripts/mcp.ts"],
      env: { ...(process.env as Record<string, string>), CLUSTER: "devnet", RPC_URL: rpc.url, WALLET: wallet },
      stderr: "ignore",
    }),
  );
});
after(async () => {
  await client?.close();
  rpc.server.close();
});

const call = async (name: string, args: Record<string, unknown> = {}) => {
  const res: any = await client.callTool({ name, arguments: args });
  return { json: JSON.parse(res.content[0].text), isError: !!res.isError };
};

test("el servidor MCP expone las herramientas de OwnCurve y simula antes de escribir", { timeout: 300_000 }, async () => {
  const { tools } = await client.listTools();
  const names = tools.map((t) => t.name);
  for (const n of ["owncurve_list", "owncurve_show", "owncurve_launch", "owncurve_propose", "owncurve_object", "owncurve_defend_floor", "owncurve_redeem", "owncurve_tender_offer", "owncurve_declare_abandoned", "owncurve_observe"])
    assert.ok(names.includes(n), `falta ${n}`);
  const launch = tools.find((t) => t.name === "owncurve_launch")!;
  assert.ok((launch.inputSchema as any).properties.confirm, "las escrituras llevan `confirm`");
  assert.equal(tools.find((t) => t.name === "owncurve_show")!.annotations?.readOnlyHint, true);

  const dry = await call("owncurve_launch", { name: "MCP Labs", symbol: "mcp" });
  assert.equal(dry.json.dryRun, true, JSON.stringify(dry.json));
  assert.equal(dry.json.wouldSucceed, true);
  assert.deepEqual((await call("owncurve_list")).json, [], "la simulación no creó nada");

  const real = await call("owncurve_launch", { name: "MCP Labs", symbol: "mcp", threshold: 0.5, confirm: true });
  assert.equal(real.json.ok, true, JSON.stringify(real.json));
  const s = await call("owncurve_show", { config: real.json.config });
  assert.equal(s.json.state, "bonding");
  assert.ok(s.json.can.includes("buy"));
  assert.equal(s.json.quote.symbol, "SOL");

  const bad = await call("owncurve_propose", { config: real.json.config, evidence: "https://x.io", confirm: true });
  assert.equal(bad.isError, true, "los errores del programa se marcan como error de la herramienta");
});
