// OwnCurve keeper: runs every 10 minutes on GitHub Actions (.github/workflows/keeper.yml) and does
// every permissionless job that keeps holder protections live, with no human in the loop:
//   harvest graduated curves · arm guards · settle tranches whose window closed · record DAMM v2
//   prices for the TWAP · defend floors below backing · return treasuries of silent teams.
//
//   CLUSTER=devnet RPC_URL=https://api.devnet.solana.com WALLET=keeper.json npx tsx scripts/keeper.ts
import { PublicKey } from "@solana/web3.js";
import bs58 from "bs58";
import fs from "fs";
import { loadIdl, makeNet } from "./lib/net";
import { OwnCurve, Raise, stateName } from "./lib/owncurve";

const MAX_ACTIONS = Number(process.env.KEEPER_MAX_ACTIONS ?? 25);

type Action = { raise: string; action: string; ok: boolean; signature?: string; error?: string };

async function main() {
  const net = await makeNet();
  const oc = new OwnCurve(net, loadIdl());
  const idl = loadIdl() as any;
  const disc = idl.accounts.find((a: any) => a.name === "Raise").discriminator as number[];
  const raw = await net.conn.getProgramAccounts(oc.programId, {
    filters: [{ memcmp: { offset: 0, bytes: bs58.encode(Uint8Array.from(disc)) } }],
  });
  const balance = (await net.conn.getBalance(net.payer.publicKey)) / 1e9;
  console.log(`keeper ${net.payer.publicKey.toBase58()} · ${balance.toFixed(4)} SOL · ${raw.length} raise accounts`);
  if (balance < 0.01) throw new Error("Keeper balance too low");

  const now = (await net.conn.getBlockTime(await net.conn.getSlot()).catch(() => null)) ?? Math.floor(Date.now() / 1000);
  const actions: Action[] = [];
  const act = async (r: Raise, action: string, fn: () => Promise<string | void>) => {
    if (actions.length >= MAX_ACTIONS) return;
    try {
      const sig = (await fn()) || undefined;
      actions.push({ raise: r.config.toBase58(), action, ok: true, signature: sig });
      console.log(`  ✔ ${action.padEnd(18)} ${r.config.toBase58()} ${sig ?? ""}`);
    } catch (e: any) {
      const logs: string[] = e?.logs ?? [];
      const err = logs.join("\n").match(/Error Code: (\w+)/)?.[1] ?? String(e?.message ?? e).slice(0, 120);
      actions.push({ raise: r.config.toBase58(), action, ok: false, error: err });
      console.log(`  ✘ ${action.padEnd(18)} ${r.config.toBase58()} ${err}`);
    }
  };

  for (const { account } of raw) {
    let a: any;
    try {
      a = oc.program.coder.accounts.decode("raise", account.data);
    } catch {
      continue; // versión antigua
    }
    const state = stateName(a.state);
    if (!["bonding", "funded", "completed"].includes(state)) continue;
    const config = new PublicKey(a.dbcConfig);
    let r: Raise;
    try {
      r = await Raise.load(oc, config);
    } catch {
      continue;
    }
    if (r.baseMint.equals(PublicKey.default)) continue;
    const curve = await oc.curve(r).catch(() => null);
    if (!curve) continue;

    if (state === "bonding") {
      if (curve.complete) await act(r, "harvest", () => oc.harvest(r));
      continue;
    }
    const g = await oc.guardState(r).catch(() => null);
    const pool = ps(await oc.dbc.state.getPool(r.pool).catch(() => null));
    const migrated = Boolean(pool?.isMigrated);

    if (state === "funded") {
      if (g && g.armedAt === 0) await act(r, "arm_guard", () => oc.armGuard(r));
      const proposed = (a.milestones as any[]).slice(0, Number(a.milestoneCount)).some((m) => stateName(m.status) === "proposed");
      if (proposed && now >= Number(a.proposalEndsAt)) await act(r, "settle", () => oc.finalize(r));
      else if (!proposed && g && g.abandonableAt !== null && now >= g.abandonableAt && !g.abandoned)
        await act(r, "declare_abandoned", () => oc.declareAbandoned(r));
    }
    if (migrated && g && !g.acquired && now >= g.nextObserveAt) await act(r, "observe", () => oc.observe(r));
    if (migrated) {
      const amount = await oc.suggestDefend(r).catch(() => null);
      if (amount && amount.gtn(0)) await act(r, "defend_floor", () => oc.defendFloor(r, amount));
    }
  }

  const summary = { at: new Date().toISOString(), keeper: net.payer.publicKey.toBase58(), balance, actions };
  fs.writeFileSync(process.env.KEEPER_OUT ?? "keeper-run.json", JSON.stringify(summary, null, 2));
  console.log(`${actions.filter((x) => x.ok).length} actions done, ${actions.filter((x) => !x.ok).length} failed`);
}

const ps = (p: any) => (p ? (p.poolState ?? p) : null);

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error(`✘ ${e.message ?? e}`);
    process.exit(1);
  });
