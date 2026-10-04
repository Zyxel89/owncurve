// OwnCurve CLI — the same client as the web app, with JSON output for scripts and AI agents.
//
//   npx tsx scripts/cli.ts <command> [config] [--param value ...] [--yes]
//
// Reads never sign anything. Every command that writes is a DRY RUN unless --yes is given:
// the first transaction is simulated against the network and the result is printed.
//
// Env: RPC_URL (devnet RPC), WALLET (keypair file, default ~/.config/solana/id.json),
//      CLUSTER=local (LiteSVM, for tests).
import { COMMANDS, runCommand } from "./lib/agent";
import { makeNet } from "./lib/net";

function help() {
  const lines = ["owncurve <command> [config] [--param value ...] [--yes]", "JSON on stdout. Writes are simulated unless --yes is passed.", ""];
  for (const who of ["anyone", "team", "holder"] as const) {
    lines.push(who === "anyone" ? "Anyone" : who === "team" ? "Team" : "Holder");
    for (const c of COMMANDS.filter((c) => c.who === who)) {
      const ps = c.params
        .filter((p) => p.name !== "config")
        .map((p) => (p.required ? `--${p.name} <${p.type}>` : `[--${p.name}]`))
        .join(" ");
      const head = `  ${c.name}${c.params.some((p) => p.name === "config") ? " <config>" : ""} ${ps}`;
      lines.push(head.padEnd(58) + c.description.split(":")[0].split(".")[0]);
    }
    lines.push("");
  }
  return lines.join("\n");
}

type Args = { _: string[]; [k: string]: string | boolean | string[] };
function parseArgs(argv: string[]): Args {
  const out: Args = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith("--")) {
      const key = a.slice(2);
      const next = argv[i + 1];
      if (next === undefined || next.startsWith("--")) out[key] = true;
      else out[key] = argv[++i];
    } else out._.push(a);
  }
  return out;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const [cmd, config] = args._;
  if (!cmd || cmd === "help" || args.help) {
    process.stdout.write(help() + "\n");
    return 0;
  }
  const input: Record<string, any> = { ...args, config };
  delete input._;
  // alias anteriores: --sol (buy/defend-floor) y --amount (object/redeem)
  if (input.sol !== undefined && input.spend === undefined) input.spend = input.sol;
  if (input.amount !== undefined && input.tokens === undefined) input.tokens = input.amount;
  const out = await runCommand(await makeNet(), cmd, input, { yes: args.yes === true });
  console.log(JSON.stringify(out, null, 2));
  return out && (out as any).ok === false ? 1 : 0;
}

main()
  .then((code) => process.exit(code))
  .catch((e) => {
    console.log(JSON.stringify({ ok: false, error: String(e?.message ?? e).slice(0, 300) }, null, 2));
    process.exit(1);
  });
