// OwnCurve CLI — the same client as the web app, with JSON output for scripts and AI agents.
//
//   npx tsx scripts/cli.ts <command> [args] [--yes]
//
// Reads never sign anything. Every command that writes is a DRY RUN unless --yes is given:
// the first transaction is simulated against the network and the result is printed.
//
// Env: RPC_URL (devnet RPC), WALLET (keypair file, default ~/.config/solana/id.json),
//      CLUSTER=local (LiteSVM, for tests).
import { BN } from "@anchor-lang/core";
import { Keypair, LAMPORTS_PER_SOL, PublicKey, Transaction, TransactionInstruction } from "@solana/web3.js";
import { Net, loadIdl, makeNet } from "./lib/net";
import { BASE_DECIMALS, DEFAULT_PARAMS, OwnCurve, Raise, evidence, stateName } from "./lib/owncurve";

const HELP = `owncurve <command> [args]   (JSON on stdout; writes need --yes, otherwise they are simulated)

Read
  list                                   every raise: state, treasury, progress
  show <config>                          one raise: tranches, proposal + evidence, price vs backing,
                                         your balance and the actions you can take now ("can")
Team
  launch --name N --symbol S [--threshold 0.5] [--treasury 80] [--tranches 30,30,40]
         [--window 60] [--quorum 10] [--floor 20]
  propose <config> --evidence URL [--note TEXT]   request the next tranche (sha256(note|URL) on-chain)
Anyone
  buy <config> --sol X                   buy on the bonding curve
  harvest <config>                       move the graduated raise into the treasury
  migrate <config>                       graduate the pool to Meteora DAMM v2
  collect-fees <config>                  curve trading fees -> treasury
  settle <config>                        pay the tranche, or open redemptions if quorum objected
  defend-floor <config> [--sol X]        treasury buys back below backing and burns (default: suggested)
Holder
  object <config> [--amount TOKENS]      lock tokens against the pending tranche (default: all)
  unlock <config>                        get voted tokens back after settlement
  redeem <config> [--amount TOKENS]      in liquidation: burn tokens for a share of the treasury
`;

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

const sol = (v: BN | number | bigint) => Number(v.toString()) / LAMPORTS_PER_SOL;
const tokens = (v: BN) => Number(v.toString()) / 10 ** BASE_DECIMALS;
const toTokens = (x: string) => new BN(Math.round(Number(x) * 10 ** BASE_DECIMALS).toString());
const toLamports = (x: string) => new BN(Math.round(Number(x) * LAMPORTS_PER_SOL).toString());
const DEFAULT = PublicKey.default;

class DryRun extends Error {
  constructor(public result: any) {
    super("dry-run");
  }
}

/** Net that simulates the first transaction instead of sending it. */
function dryNet(net: Net): Net {
  return {
    ...net,
    send: async (label: string, ixs: TransactionInstruction[], signers: Keypair[]) => {
      const tx = new Transaction().add(...ixs);
      tx.feePayer = net.payer.publicKey;
      tx.recentBlockhash = (await net.conn.getLatestBlockhash()).blockhash;
      const all = [net.payer, ...signers].filter((k, i, arr) => arr.findIndex((x) => x.publicKey.equals(k.publicKey)) === i);
      tx.sign(...all);
      const sim = await net.conn.simulateTransaction(tx);
      throw new DryRun({
        dryRun: true,
        transaction: label,
        wouldSucceed: !sim.value.err,
        error: sim.value.err ?? undefined,
        computeUnits: sim.value.unitsConsumed,
        logs: sim.value.err ? sim.value.logs?.slice(-12) : undefined,
        hint: "Run again with --yes to send it.",
      });
    },
  };
}

async function raiseFor(oc: OwnCurve, config: string) {
  const configKey = new PublicKey(config);
  const pda = PublicKey.findProgramAddressSync([Buffer.from("raise"), configKey.toBuffer()], oc.programId)[0];
  const raise = await (oc.program.account as any).raise.fetch(pda);
  return { r: new Raise(oc, configKey, new PublicKey(raise.baseMint)), raise };
}

async function listRaises(oc: OwnCurve) {
  const idl = loadIdl() as any;
  const disc = idl.accounts.find((a: any) => a.name === "Raise").discriminator as number[];
  const bs58 = (await import("bs58")).default;
  const raw = await oc.net.conn.getProgramAccounts(oc.programId, {
    filters: [{ memcmp: { offset: 0, bytes: bs58.encode(Uint8Array.from(disc)) } }],
  });
  const out: any[] = [];
  for (const { account } of raw) {
    let a: any;
    try {
      a = oc.program.coder.accounts.decode("raise", account.data);
    } catch {
      continue; // older program version
    }
    const config = new PublicKey(a.dbcConfig);
    const baseMint = new PublicKey(a.baseMint);
    const r = new Raise(oc, config, baseMint);
    const bound = !baseMint.equals(DEFAULT);
    out.push({
      config: config.toBase58(),
      state: stateName(a.state),
      baseMint: bound ? baseMint.toBase58() : null,
      team: new PublicKey(a.team).toBase58(),
      fundedSol: sol(a.fundedAmount),
      releasedSol: sol(a.releasedAmount),
      treasurySol: bound ? sol(await oc.tokenBalance(r.treasuryQuote)) : 0,
    });
  }
  return out;
}

async function show(oc: OwnCurve, config: string) {
  const { r, raise } = await raiseFor(oc, config);
  const state = stateName(raise.state);
  const me = oc.net.payer.publicKey;
  const bound = !r.baseMint.equals(DEFAULT);
  const funded = new BN(raise.fundedAmount.toString());
  const floorReserve = funded.muln(raise.floorReserveBps).divn(10_000);
  const payable = funded.sub(floorReserve);
  const count = Number(raise.milestoneCount);
  let acc = new BN(0);
  const milestones = (raise.milestones as any[]).slice(0, count).map((m, i) => {
    const amount = i === count - 1 ? payable.sub(acc) : payable.muln(m.trancheBps).divn(10_000);
    acc = acc.add(amount);
    return {
      index: i + 1,
      pct: m.trancheBps / 100,
      sol: sol(amount),
      status: stateName(m.status),
      evidenceSha256: m.evidenceHash.some((b: number) => b) ? Buffer.from(m.evidenceHash).toString("hex") : null,
    };
  });

  let curve: any = null;
  let market: any = null;
  let backing: any = null;
  let wallet: any = null;
  if (bound) {
    const c = await oc.curve(r).catch(() => null);
    const pool = await oc.dbc.state.getPool(r.pool).catch(() => null);
    const migrated = Boolean(pool && (pool as any).isMigrated) || Boolean(pool && (pool as any).poolState?.isMigrated);
    if (c) curve = { raisedSol: sol(c.reserve), targetSol: sol(c.threshold), complete: c.reserve.gte(c.threshold), migrated };
    const b = await oc.backing(r);
    const perM = (u: number) => (u * 10 ** BASE_DECIMALS * 1_000_000) / LAMPORTS_PER_SOL;
    backing = { treasurySol: sol(b.treasuryQuote), circulatingTokens: tokens(b.circulating), solPerMillionTokens: perM(b.perUnit) };
    if (migrated) {
      const st = await oc.dammState(r).catch(() => null);
      if (st) {
        const suggest = ["funded", "completed"].includes(state) ? await oc.suggestDefend(r) : new BN(0);
        market = {
          pool: st.pool.toBase58(),
          priceSolPerMillionTokens: perM(st.price),
          belowBacking: st.price < b.perUnit,
          suggestedDefendSol: sol(suggest),
        };
      }
    }
    const nonce = Number(raise.proposalNonce);
    const votes: { nonce: number; tokens: number }[] = [];
    for (let n = 0; n <= nonce; n++) {
      const info = await oc.net.conn.getAccountInfo(r.voteRecord(me, n));
      if (info) votes.push({ nonce: n, tokens: tokens(new BN(oc.program.coder.accounts.decode("voteRecord", info.data).amount.toString())) });
    }
    wallet = {
      address: me.toBase58(),
      sol: (await oc.net.conn.getBalance(me)) / LAMPORTS_PER_SOL,
      tokens: tokens(await oc.tokenBalance(r.baseAta(me))),
      votes,
      isTeam: me.equals(new PublicKey(raise.team)),
    };
  }

  const active = milestones.findIndex((m) => m.status === "proposed");
  const now = (await oc.net.conn.getBlockTime(await oc.net.conn.getSlot())) ?? Math.floor(Date.now() / 1000);
  const endsAt = Number(raise.proposalEndsAt.toString());
  const proposal =
    state === "funded" && active >= 0
      ? {
          tranche: active + 1,
          evidenceUri: raise.proposalEvidenceUri,
          evidenceSha256: milestones[active].evidenceSha256,
          objectionsCloseAt: new Date(endsAt * 1000).toISOString(),
          secondsLeft: Math.max(0, endsAt - now),
          objectingTokens: tokens(new BN(raise.proposalRejectWeight.toString())),
          quorumTokens: backing ? (backing.circulatingTokens * raise.rejectQuorumBps) / 10_000 : null,
        }
      : null;

  // What this wallet can do right now
  const can: string[] = [];
  if (state === "bonding" && curve && !curve.complete) can.push("buy");
  if (state === "bonding" && curve?.complete) can.push("harvest");
  if (["funded", "completed", "liquidating"].includes(state) && curve && !curve.migrated) can.push("migrate");
  if (["funded", "completed", "liquidating"].includes(state)) can.push("collect-fees");
  if (state === "funded" && !proposal && wallet?.isTeam && milestones.some((m) => m.status === "locked")) can.push("propose");
  if (proposal && proposal.secondsLeft > 0 && wallet?.tokens > 0) can.push("object");
  if (proposal && proposal.secondsLeft === 0) can.push("settle");
  if (wallet?.votes.some((v: any) => v.nonce < Number(raise.proposalNonce))) can.push("unlock");
  if (state === "liquidating" && wallet?.tokens > 0) can.push("redeem");
  if (market?.suggestedDefendSol > 0) can.push("defend-floor");

  return {
    config,
    state,
    team: new PublicKey(raise.team).toBase58(),
    baseMint: bound ? r.baseMint.toBase58() : null,
    treasury: r.treasury.toBase58(),
    rules: {
      treasuryPctMin: raise.minTreasuryPct,
      challengeWindowSecs: Number(raise.challengeWindow),
      rejectQuorumPct: raise.rejectQuorumBps / 100,
      floorReservePct: raise.floorReserveBps / 100,
    },
    fundedSol: sol(funded),
    payableToTeamSol: sol(payable),
    releasedSol: sol(raise.releasedAmount),
    feesCollectedSol: sol(raise.feesCollected),
    floor: { reserveSol: sol(floorReserve), spentSol: sol(raise.floorSpent), tokensBurned: tokens(new BN(raise.tokensBurned.toString())) },
    milestones,
    proposal,
    curve,
    backing,
    market,
    wallet,
    can,
  };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const [cmd, config] = args._;
  if (!cmd || cmd === "help" || args.help) {
    process.stdout.write(HELP);
    return;
  }
  const base = await makeNet();
  const yes = args.yes === true;
  const net = yes || ["list", "show"].includes(cmd) ? base : dryNet(base);
  const oc = new OwnCurve(net, loadIdl());
  const need = (k: string) => {
    const v = args[k];
    if (typeof v !== "string" || !v) throw new Error(`Missing --${k}`);
    return v;
  };
  const needConfig = () => {
    if (!config) throw new Error(`Usage: ${cmd} <config>`);
    return raiseFor(oc, config);
  };
  const done = (sig: string | void, extra: object = {}) => ({ ok: true, signature: sig ?? null, explorer: sig ? base.explorer(sig) : null, ...extra });

  let out: any;
  switch (cmd) {
    case "list":
      out = await listRaises(oc);
      break;
    case "show":
      if (!config) throw new Error("Usage: show <config>");
      out = await show(oc, config);
      break;
    case "launch": {
      const params = {
        ...DEFAULT_PARAMS,
        thresholdSol: Number(args.threshold ?? 0.5),
        treasuryPct: Number(args.treasury ?? 80),
        tranchesBps: String(args.tranches ?? "30,30,40").split(",").map((t) => Math.round(Number(t) * 100)),
        challengeSecs: Number(args.window ?? 60),
        quorumBps: Math.round(Number(args.quorum ?? 10) * 100),
        floorReserveBps: Math.round(Number(args.floor ?? 20) * 100),
      };
      const configKp = Keypair.generate();
      await oc.createRaise(params, configKp);
      const { sig } = await oc.launchPool(configKp.publicKey, Keypair.generate(), undefined, true, {
        name: need("name"),
        symbol: need("symbol").toUpperCase(),
        uri: String(args.uri ?? "https://raw.githubusercontent.com/solana-developers/opos-asset/main/assets/DeveloperPortal/metadata.json"),
      });
      out = done(sig, { config: configKp.publicKey.toBase58() });
      break;
    }
    case "buy": {
      const { r } = await needConfig();
      out = done(await oc.buy(r, toLamports(need("sol"))));
      break;
    }
    case "harvest": {
      const { r } = await needConfig();
      out = done(await oc.harvest(r));
      break;
    }
    case "migrate": {
      const { r } = await needConfig();
      out = done((await oc.migrate(r)).sig);
      break;
    }
    case "collect-fees": {
      const { r } = await needConfig();
      out = done(await oc.collectTradingFees(r));
      break;
    }
    case "propose": {
      const { r } = await needConfig();
      const ev = await evidence(need("evidence"), typeof args.note === "string" ? args.note : undefined);
      out = done(await oc.propose(r, undefined, ev), { evidenceUri: ev.uri, evidenceSha256: Buffer.from(ev.hash).toString("hex") });
      break;
    }
    case "object": {
      const { r } = await needConfig();
      const amount = typeof args.amount === "string" ? toTokens(args.amount) : await oc.tokenBalance(r.baseAta(base.payer.publicKey));
      out = done(await oc.reject(r, base.payer, amount), { tokens: tokens(amount) });
      break;
    }
    case "settle": {
      const { r } = await needConfig();
      out = done(await oc.finalize(r));
      break;
    }
    case "unlock": {
      const { r, raise } = await needConfig();
      let sig: string | void = undefined;
      for (let n = 0; n < Number(raise.proposalNonce); n++) {
        if (await base.conn.getAccountInfo(r.voteRecord(base.payer.publicKey, n))) sig = await oc.withdrawVote(r, base.payer, n);
      }
      out = done(sig);
      break;
    }
    case "redeem": {
      const { r } = await needConfig();
      const amount = typeof args.amount === "string" ? toTokens(args.amount) : await oc.tokenBalance(r.baseAta(base.payer.publicKey));
      out = done(await oc.redeem(r, base.payer, amount), { tokens: tokens(amount) });
      break;
    }
    case "defend-floor": {
      const { r } = await needConfig();
      const amount = typeof args.sol === "string" ? toLamports(args.sol) : await oc.suggestDefend(r);
      if (amount.isZero()) {
        out = { ok: false, reason: "The market price is not below the treasury backing (or the floor budget is empty)." };
        break;
      }
      out = done(await oc.defendFloor(r, amount), { spentSol: sol(amount) });
      break;
    }
    default:
      throw new Error(`Unknown command "${cmd}". Run: owncurve help`);
  }
  console.log(JSON.stringify(out, null, 2));
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    if (e instanceof DryRun) {
      console.log(JSON.stringify(e.result, null, 2));
      process.exit(0);
    }
    const logs: string[] = e?.logs ?? [];
    const named = logs.join("\n").match(/Error Code: (\w+)/)?.[1];
    console.log(JSON.stringify({ ok: false, error: named ?? String(e?.message ?? e).slice(0, 300) }, null, 2));
    process.exit(1);
  });
