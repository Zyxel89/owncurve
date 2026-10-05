// Operaciones de OwnCurve para agentes: las usan el CLI (scripts/cli.ts) y el servidor MCP
// (scripts/mcp.ts). Todo devuelve JSON plano. Las escrituras se SIMULAN salvo que `yes` sea true.
import { BN } from "@anchor-lang/core";
import { Keypair, LAMPORTS_PER_SOL, PublicKey, Transaction, TransactionInstruction } from "@solana/web3.js";
import bs58 from "bs58";
import { Net, loadIdl } from "./net";
import { BASE_DECIMALS, DEFAULT_GUARD, DEFAULT_PARAMS, OwnCurve, Quote, Raise, SOL_QUOTE, evidence, stateName } from "./owncurve";

export type ParamSpec = { name: string; type: "string" | "number"; required?: boolean; description: string };
export type CommandSpec = { name: string; write: boolean; who: "anyone" | "team" | "holder"; description: string; params: ParamSpec[] };

const CONFIG: ParamSpec = { name: "config", type: "string", required: true, description: "Raise address (its Meteora DBC config)" };

export const COMMANDS: CommandSpec[] = [
  { name: "list", write: false, who: "anyone", description: "List every OwnCurve raise with its state, currency, funded amount and treasury.", params: [] },
  {
    name: "show",
    write: false,
    who: "anyone",
    description:
      "Full state of one raise: tranches, pending proposal with evidence link and SHA-256, curve progress, market price vs treasury backing, this wallet's balances and votes, and `can`: the actions this wallet can take right now.",
    params: [CONFIG],
  },
  {
    name: "launch",
    write: true,
    who: "team",
    description: "Launch a new raise: a Meteora DBC curve whose graduation fee funds an OwnCurve treasury that pays the team in milestone tranches.",
    params: [
      { name: "name", type: "string", required: true, description: "Token name" },
      { name: "symbol", type: "string", required: true, description: "Token symbol" },
      { name: "quote", type: "string", description: "Currency to raise in: 'SOL' (default) or the mint address of an SPL / Token-2022 token (USDC, an xStock…)" },
      { name: "threshold", type: "number", description: "Amount the curve raises before graduating, in the raise currency (default 0.5)" },
      { name: "treasury", type: "number", description: "% of the raise that goes to the treasury, 50–99 (default 80)" },
      { name: "tranches", type: "string", description: "Comma-separated % per milestone, summing to 100 (default 30,30,40)" },
      { name: "window", type: "number", description: "Seconds holders have to object to each tranche, ≥ 60 (default 60)" },
      { name: "quorum", type: "number", description: "% of circulating supply that blocks a tranche, ≤ 30 (default 10)" },
      { name: "floor", type: "number", description: "% of the treasury kept as a price-floor reserve, 0–50 (default 20)" },
      { name: "inactivity", type: "number", description: "Ghost-team guard: seconds without a tranche request after which anyone can return the treasury to holders (default 300 on devnet)" },
      { name: "premium", type: "number", description: "On-chain Bedrock clause: % over the TWAP a takeover must pay every holder, 10–100 (default 30)" },
      { name: "twap", type: "number", description: "TWAP window in seconds for the takeover price (default 120)" },
    ],
  },
  {
    name: "propose",
    write: true,
    who: "team",
    description: "Request the next milestone tranche with a public evidence link; the SHA-256 of `note` (or of the link) is stored on-chain.",
    params: [
      CONFIG,
      { name: "evidence", type: "string", required: true, description: "URL of the delivered work (≤ 160 chars)" },
      { name: "note", type: "string", description: "What was shipped; its SHA-256 is committed on-chain" },
    ],
  },
  { name: "buy", write: true, who: "anyone", description: "Buy the token on the bonding curve.", params: [CONFIG, { name: "spend", type: "number", required: true, description: "Amount to spend, in the raise currency" }] },
  { name: "harvest", write: true, who: "anyone", description: "After the curve completes, move the raise into the treasury (CPI withdraw_migration_fee).", params: [CONFIG] },
  { name: "migrate", write: true, who: "anyone", description: "Graduate the pool to Meteora DAMM v2; the treasury receives the locked LP position.", params: [CONFIG] },
  { name: "collect-fees", write: true, who: "anyone", description: "Move the curve's partner trading fees into the treasury.", params: [CONFIG] },
  { name: "settle", write: true, who: "anyone", description: "After the objection window: pay the tranche, or open redemptions if objections reached quorum.", params: [CONFIG] },
  {
    name: "defend-floor",
    write: true,
    who: "anyone",
    description: "When the DAMM v2 price is below the treasury backing, make the treasury buy tokens back (never above backing) and burn them.",
    params: [CONFIG, { name: "spend", type: "number", description: "Amount to spend in the raise currency (default: suggested amount)" }],
  },
  { name: "observe", write: true, who: "anyone", description: "Record the DAMM v2 price into the raise's on-chain TWAP (needed before a takeover).", params: [CONFIG] },
  {
    name: "declare-abandoned",
    write: true,
    who: "anyone",
    description: "Ghost-team protection: if the team has not requested a tranche within the guard's inactivity window, return the treasury to holders (redemptions open).",
    params: [CONFIG],
  },
  {
    name: "tender-offer",
    write: true,
    who: "anyone",
    description:
      "On-chain Bedrock clause: take over the raise by topping up the treasury so every holder can redeem at TWAP × (1 + premium). The acquirer becomes the team; holders redeem.",
    params: [CONFIG, { name: "max", type: "number", description: "Most you are willing to deposit, in the raise currency (default: quoted amount + 2%)" }],
  },
  {
    name: "object",
    write: true,
    who: "holder",
    description: "Lock tokens as an objection to the pending tranche.",
    params: [CONFIG, { name: "tokens", type: "number", description: "Tokens to lock (default: all in the wallet)" }],
  },
  { name: "unlock", write: true, who: "holder", description: "Return tokens locked in objections once the tranche is settled.", params: [CONFIG] },
  {
    name: "redeem",
    write: true,
    who: "holder",
    description: "In liquidation: burn tokens for a pro-rata share of the treasury.",
    params: [CONFIG, { name: "tokens", type: "number", description: "Tokens to redeem (default: all in the wallet)" }],
  },
];

const ui = (v: BN | number | bigint | { toString(): string }, decimals: number) => Number(v.toString()) / 10 ** decimals;
const toUnits = (x: number, decimals: number) => new BN(Math.round(x * 10 ** decimals).toString());
const tokens = (v: BN | { toString(): string }) => ui(v, BASE_DECIMALS);
const DEFAULT = PublicKey.default;

class DryRun extends Error {
  constructor(public result: any) {
    super("dry-run");
  }
}

/** Net que simula la primera transacción en vez de enviarla. */
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
        hint: "Nothing was sent. Repeat with yes=true (CLI: --yes) to send it.",
      });
    },
  };
}

async function raiseFor(oc: OwnCurve, config: string) {
  const r = await Raise.load(oc, new PublicKey(config));
  const raise = await r.fetch();
  const quote = await oc.quoteInfo(r.quoteMint);
  return { r, raise, quote };
}

const quoteJson = (q: Quote) => ({ symbol: q.symbol, mint: q.mint.toBase58(), decimals: q.decimals });

async function listRaises(oc: OwnCurve) {
  const idl = loadIdl() as any;
  const disc = idl.accounts.find((a: any) => a.name === "Raise").discriminator as number[];
  const raw = await oc.net.conn.getProgramAccounts(oc.programId, {
    filters: [{ memcmp: { offset: 0, bytes: bs58.encode(Uint8Array.from(disc)) } }],
  });
  const out: any[] = [];
  for (const { account } of raw) {
    let a: any;
    try {
      a = oc.program.coder.accounts.decode("raise", account.data);
    } catch {
      continue; // versión antigua del programa
    }
    const config = new PublicKey(a.dbcConfig);
    const baseMint = new PublicKey(a.baseMint);
    const bound = !baseMint.equals(DEFAULT);
    const qm = new PublicKey(a.quoteMint);
    const q = qm.equals(DEFAULT) ? SOL_QUOTE : await oc.quoteInfo(qm).catch(() => SOL_QUOTE);
    const r = new Raise(oc, config, baseMint, q.mint, q.program);
    out.push({
      config: config.toBase58(),
      state: stateName(a.state),
      quote: q.symbol,
      baseMint: bound ? baseMint.toBase58() : null,
      team: new PublicKey(a.team).toBase58(),
      funded: ui(a.fundedAmount, q.decimals),
      released: ui(a.releasedAmount, q.decimals),
      treasury: bound ? ui(await oc.tokenBalance(r.treasuryQuote), q.decimals) : 0,
    });
  }
  return out;
}

async function show(oc: OwnCurve, config: string) {
  const { r, raise, quote: q } = await raiseFor(oc, config);
  const d = q.decimals;
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
      amount: ui(amount, d),
      status: stateName(m.status),
      evidenceSha256: m.evidenceHash.some((b: number) => b) ? Buffer.from(m.evidenceHash).toString("hex") : null,
    };
  });

  let curve: any = null;
  let market: any = null;
  let backing: any = null;
  let wallet: any = null;
  // precio en "moneda por 1.000.000 de tokens"
  const perM = (unitsPerAtom: number) => (unitsPerAtom * 10 ** BASE_DECIMALS * 1_000_000) / 10 ** d;
  if (bound) {
    const c = await oc.curve(r).catch(() => null);
    const pool = await oc.dbc.state.getPool(r.pool).catch(() => null);
    const migrated = Boolean(pool && (pool as any).isMigrated) || Boolean(pool && (pool as any).poolState?.isMigrated);
    if (c) curve = { raised: ui(c.reserve, d), target: ui(c.threshold, d), complete: c.reserve.gte(c.threshold), migrated };
    const b = await oc.backing(r);
    backing = { treasury: ui(b.treasuryQuote, d), circulatingTokens: tokens(b.circulating), perMillionTokens: perM(b.perUnit) };
    if (migrated) {
      const st = await oc.dammState(r).catch(() => null);
      if (st) {
        const suggest = ["funded", "completed"].includes(state) ? await oc.suggestDefend(r) : new BN(0);
        market = { pool: st.pool.toBase58(), pricePerMillionTokens: perM(st.price), belowBacking: st.price < b.perUnit, suggestedDefend: ui(suggest, d) };
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
      quote: r.isSol ? undefined : ui(await oc.tokenBalance(r.quoteAta(me)), d),
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

  let guard: any = null;
  const gs = bound ? await oc.guardState(r).catch(() => null) : null;
  if (gs) {
    guard = {
      ghostTeam: {
        inactivitySecs: gs.inactivitySecs,
        armed: gs.armedAt > 0,
        abandonableAt: gs.abandonableAt ? new Date(gs.abandonableAt * 1000).toISOString() : null,
        secondsLeft: gs.abandonableAt ? Math.max(0, gs.abandonableAt - gs.now) : null,
        abandoned: gs.abandoned,
      },
      bedrock: {
        premiumPct: gs.buyoutPremiumBps / 100,
        twapWindowSecs: gs.twapWindowSecs,
        observationsInWindow: gs.observationsInWindow,
        twapReady: gs.twapReady,
        twapPerMillionTokens: perM(gs.twap),
        buyoutPerMillionTokens: perM(gs.buyoutPrice),
        depositToTakeOver: ui(gs.buyoutDeposit, d),
        nextObserveInSecs: Math.max(0, gs.nextObserveAt - gs.now),
        acquirer: gs.acquired ? gs.acquirer.toBase58() : null,
      },
    };
  }

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
  if (market?.suggestedDefend > 0) can.push("defend-floor");
  if (guard && ["funded", "completed"].includes(state) && curve?.migrated && guard.bedrock.nextObserveInSecs === 0) can.push("observe");
  if (guard && state === "funded" && !proposal && guard.ghostTeam.secondsLeft === 0) can.push("declare-abandoned");
  if (guard && ["funded", "completed"].includes(state) && guard.bedrock.twapReady) can.push("tender-offer");

  return {
    config,
    state,
    quote: quoteJson(q),
    team: new PublicKey(raise.team).toBase58(),
    baseMint: bound ? r.baseMint.toBase58() : null,
    treasury: r.treasury.toBase58(),
    rules: {
      treasuryPctMin: raise.minTreasuryPct,
      challengeWindowSecs: Number(raise.challengeWindow),
      rejectQuorumPct: raise.rejectQuorumBps / 100,
      floorReservePct: raise.floorReserveBps / 100,
    },
    funded: ui(funded, d),
    payableToTeam: ui(payable, d),
    released: ui(raise.releasedAmount, d),
    feesCollected: ui(raise.feesCollected, d),
    floor: { reserve: ui(floorReserve, d), spent: ui(raise.floorSpent, d), tokensBurned: tokens(new BN(raise.tokensBurned.toString())) },
    milestones,
    proposal,
    curve,
    backing,
    market,
    guard,
    wallet,
    can,
  };
}

/** Ejecuta un comando. `input` usa los nombres de COMMANDS. */
export async function runCommand(base: Net, cmd: string, input: Record<string, any>, opts: { yes?: boolean } = {}) {
  const spec = COMMANDS.find((c) => c.name === cmd);
  if (!spec) throw new Error(`Unknown command "${cmd}"`);
  for (const p of spec.params) {
    if (p.required && (input[p.name] === undefined || input[p.name] === "")) throw new Error(`Missing ${p.name}`);
  }
  const net = spec.write && !opts.yes ? dryNet(base) : base;
  const oc = new OwnCurve(net, loadIdl());
  const done = (sig: string | void, extra: object = {}) => ({ ok: true, signature: sig ?? null, explorer: sig ? base.explorer(sig) : null, ...extra });
  const num = (k: string, def?: number) => (input[k] === undefined || input[k] === "" ? def : Number(input[k]));

  try {
    switch (cmd) {
      case "list":
        return await listRaises(oc);
      case "show":
        return await show(oc, input.config);
      case "launch": {
        const qArg = String(input.quote ?? "SOL");
        const quote = qArg.toUpperCase() === "SOL" ? SOL_QUOTE : await oc.quoteInfo(new PublicKey(qArg));
        const params = {
          ...DEFAULT_PARAMS,
          quote,
          threshold: num("threshold", 0.5)!,
          treasuryPct: num("treasury", 80)!,
          tranchesBps: String(input.tranches ?? "30,30,40").split(",").map((t) => Math.round(Number(t) * 100)),
          challengeSecs: num("window", 60)!,
          quorumBps: Math.round(num("quorum", 10)! * 100),
          floorReserveBps: Math.round(num("floor", 20)! * 100),
          guard: {
            inactivitySecs: num("inactivity", DEFAULT_GUARD.inactivitySecs)!,
            buyoutPremiumBps: Math.round(num("premium", DEFAULT_GUARD.buyoutPremiumBps / 100)! * 100),
            twapWindowSecs: num("twap", DEFAULT_GUARD.twapWindowSecs)!,
          },
        };
        const configKp = Keypair.generate();
        await oc.createRaise(params, configKp);
        const { sig } = await oc.launchPool(configKp.publicKey, Keypair.generate(), undefined, true, {
          name: String(input.name),
          symbol: String(input.symbol).toUpperCase(),
          uri: String(input.uri ?? "https://raw.githubusercontent.com/solana-developers/opos-asset/main/assets/DeveloperPortal/metadata.json"),
        });
        return done(sig, { config: configKp.publicKey.toBase58(), quote: quote.symbol });
      }
      case "propose": {
        const { r } = await raiseFor(oc, input.config);
        const ev = await evidence(String(input.evidence), input.note ? String(input.note) : undefined);
        return done(await oc.propose(r, undefined, ev), { evidenceUri: ev.uri, evidenceSha256: Buffer.from(ev.hash).toString("hex") });
      }
      case "buy": {
        const { r, quote } = await raiseFor(oc, input.config);
        return done(await oc.buy(r, toUnits(num("spend")!, quote.decimals)), { spent: num("spend"), quote: quote.symbol });
      }
      case "harvest": {
        const { r } = await raiseFor(oc, input.config);
        return done(await oc.harvest(r));
      }
      case "migrate": {
        const { r } = await raiseFor(oc, input.config);
        return done((await oc.migrate(r)).sig);
      }
      case "collect-fees": {
        const { r } = await raiseFor(oc, input.config);
        return done(await oc.collectTradingFees(r));
      }
      case "settle": {
        const { r } = await raiseFor(oc, input.config);
        return done(await oc.finalize(r));
      }
      case "defend-floor": {
        const { r, quote } = await raiseFor(oc, input.config);
        const amount = num("spend") !== undefined ? toUnits(num("spend")!, quote.decimals) : await oc.suggestDefend(r);
        if (amount.isZero()) return { ok: false, reason: "The market price is not below the treasury backing (or the floor budget is empty)." };
        return done(await oc.defendFloor(r, amount), { spent: ui(amount, quote.decimals), quote: quote.symbol });
      }
      case "observe": {
        const { r } = await raiseFor(oc, input.config);
        return done(await oc.observe(r));
      }
      case "declare-abandoned": {
        const { r } = await raiseFor(oc, input.config);
        return done(await oc.declareAbandoned(r));
      }
      case "tender-offer": {
        const { r, quote } = await raiseFor(oc, input.config);
        const g = await oc.guardState(r);
        if (!g) return { ok: false, error: "This raise has no guard (launched before the guard existed)." };
        if (!g.twapReady) return { ok: false, error: `TWAP not ready: ${g.observationsInWindow} observations in the window; run observe every ${g.observeIntervalSecs}s.` };
        const max = num("max") !== undefined ? toUnits(num("max")!, quote.decimals) : g.buyoutDeposit.muln(102).divn(100).addn(1);
        return done(await oc.tenderOffer(r, max), { quotedDeposit: ui(g.buyoutDeposit, quote.decimals), max: ui(max, quote.decimals), quote: quote.symbol });
      }
      case "object": {
        const { r } = await raiseFor(oc, input.config);
        const amount = num("tokens") !== undefined ? toUnits(num("tokens")!, BASE_DECIMALS) : await oc.tokenBalance(r.baseAta(base.payer.publicKey));
        return done(await oc.reject(r, base.payer, amount), { tokens: tokens(amount) });
      }
      case "unlock": {
        const { r, raise } = await raiseFor(oc, input.config);
        let sig: string | void = undefined;
        for (let n = 0; n < Number(raise.proposalNonce); n++) {
          if (await base.conn.getAccountInfo(r.voteRecord(base.payer.publicKey, n))) sig = await oc.withdrawVote(r, base.payer, n);
        }
        return done(sig);
      }
      case "redeem": {
        const { r } = await raiseFor(oc, input.config);
        const amount = num("tokens") !== undefined ? toUnits(num("tokens")!, BASE_DECIMALS) : await oc.tokenBalance(r.baseAta(base.payer.publicKey));
        return done(await oc.redeem(r, base.payer, amount), { tokens: tokens(amount) });
      }
    }
  } catch (e: any) {
    if (e instanceof DryRun) return e.result;
    const logs: string[] = e?.logs ?? [];
    const named = logs.join("\n").match(/Error Code: (\w+)/)?.[1];
    return { ok: false, error: named ?? String(e?.message ?? e).slice(0, 300) };
  }
  throw new Error(`Unhandled command ${cmd}`);
}
