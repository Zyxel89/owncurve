// OwnCurve MCP server (stdio). Exposes the same operations as the CLI as MCP tools, so any MCP
// client (Claude Desktop, Claude Code, Cursor…) can read raises, audit milestone evidence and act
// for a holder or a team.
//
//   RPC_URL=https://api.devnet.solana.com WALLET=~/.config/solana/id.json npx tsx scripts/mcp.ts
//
// Safety: every tool that writes takes `confirm`. Without `confirm: true` it only SIMULATES the
// transaction and returns the simulation; nothing is signed or sent.
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { COMMANDS, runCommand } from "./lib/agent";
import { makeNet } from "./lib/net";

async function main() {
  const net = await makeNet();
  const server = new McpServer(
    { name: "owncurve", version: "1.0.0" },
    {
      instructions:
        "OwnCurve turns Meteora DBC launches into ownership coins: the raise sits in an on-chain treasury that pays the team in milestone tranches. " +
        "Always call owncurve_show before acting; its `can` field lists what this wallet can do now. Write tools only simulate unless confirm=true; " +
        "ask the user before confirming launch, buy, object or redeem. To audit a tranche, open proposal.evidenceUri and compare SHA-256 of the team's note with proposal.evidenceSha256.",
    },
  );

  for (const c of COMMANDS) {
    const shape: Record<string, z.ZodTypeAny> = {};
    for (const p of c.params) {
      let t: z.ZodTypeAny = p.type === "number" ? z.number() : z.string();
      t = t.describe(p.description);
      shape[p.name] = p.required ? t : t.optional();
    }
    if (c.write) shape.confirm = z.boolean().optional().describe("Send the transaction. Default false: simulate only and return the result.");
    server.registerTool(
      `owncurve_${c.name.replace(/-/g, "_")}`,
      {
        title: c.name,
        description: `${c.description}${c.write ? " Simulates unless confirm=true." : ""} (who: ${c.who})`,
        inputSchema: shape,
        annotations: { readOnlyHint: !c.write, destructiveHint: c.write, openWorldHint: true },
      },
      async (args: Record<string, any>) => {
        const { confirm, ...input } = args ?? {};
        const out = await runCommand(net, c.name, input, { yes: confirm === true });
        const failed = out && typeof out === "object" && (out as any).ok === false;
        return { content: [{ type: "text" as const, text: JSON.stringify(out, null, 2) }], isError: failed || undefined };
      },
    );
  }

  await server.connect(new StdioServerTransport());
  console.error(`owncurve MCP server ready · ${net.cluster} · wallet ${net.payer.publicKey.toBase58()}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
