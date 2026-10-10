import { BN } from "@anchor-lang/core";
import bs58 from "bs58";
import { TOKEN_2022_PROGRAM_ID, getTokenMetadata } from "@solana/spl-token";
import { Connection, Keypair, LAMPORTS_PER_SOL, PublicKey } from "@solana/web3.js";
import { useCallback, useEffect, useRef, useState } from "react";
import idl from "../../../target/idl/owncurve.json";
import type { Net } from "../../../scripts/lib/net";
import { BASE_DECIMALS, OwnCurve, Quote, Raise, SOL_QUOTE, ps, stateName } from "../../../scripts/lib/owncurve";
import { TEST_QUOTES, testQuoteOf } from "../../../scripts/lib/quotes";
import { CLUSTER } from "./browserNet";

export const IDL = idl as any;
export const PROGRAM_ID = new PublicKey(IDL.address);

/** Cliente de solo lectura (sin wallet): para listar y mostrar raises. */
export function readOnlyClient(conn: Connection) {
  const net: Net = {
    cluster: CLUSTER,
    conn,
    payer: { publicKey: PublicKey.default } as unknown as Keypair,
    send: async () => {
      throw new Error("Connect a wallet first");
    },
    explorer: (s) => s,
    advanceTime: async () => {},
    fund: async () => {},
  };
  return new OwnCurve(net, IDL);
}

export const lamportsToSol = (v: BN | number | bigint) => Number(v.toString()) / LAMPORTS_PER_SOL;
export const fmtSol = (v: BN | number | bigint, digits = 3) =>
  lamportsToSol(v).toLocaleString("en-US", { minimumFractionDigits: digits, maximumFractionDigits: digits });
/** Cantidad atómica → texto en la moneda del raise. */
export const fmtAmt = (v: BN | number | bigint, q: Quote, digits = 3) =>
  (Number(v.toString()) / 10 ** q.decimals).toLocaleString("en-US", { minimumFractionDigits: digits, maximumFractionDigits: digits });
/** Monedas de prueba de devnet con nombre legible (en mainnet: USDC, xStocks reales). */
export const KNOWN_QUOTES: (Quote & { label: string; test: boolean })[] = [
  { ...SOL_QUOTE, label: "SOL", test: false },
  ...TEST_QUOTES.map((t) => ({
    ...testQuoteOf(t),
    label: t.token2022 ? `${t.symbol} · test xStock (Token-2022)` : `${t.symbol} · test USD stablecoin`,
    test: true,
  })),
];
export async function quoteOf(oc: OwnCurve, mint: PublicKey): Promise<Quote> {
  const known = KNOWN_QUOTES.find((q) => q.mint.equals(mint));
  return known ?? oc.quoteInfo(mint);
}
export const fmtTokens = (v: BN) =>
  (Number(v.toString()) / 10 ** BASE_DECIMALS).toLocaleString("en-US", { maximumFractionDigits: 0 });

const DEFAULT = PublicKey.default;

async function tokenMeta(conn: Connection, mint: PublicKey) {
  try {
    const m = await getTokenMetadata(conn, mint, "confirmed", TOKEN_2022_PROGRAM_ID);
    if (m) return { name: m.name, symbol: m.symbol };
  } catch {
    /* sin metadata */
  }
  return { name: "Unnamed token", symbol: "?" };
}

export type RaiseRow = {
  config: string;
  name: string;
  symbol: string;
  state: string;
  treasury: number; // en la moneda del raise
  progress: number | null; // 0..1 mientras está en la curva
  funded: number;
  quote: string;
  team: string;
};

export async function listRaises(oc: OwnCurve): Promise<RaiseRow[]> {
  // Todas las cuentas Raise (por discriminador); las de versiones anteriores del programa
  // (p. ej. las de F1/F3 en devnet) tienen otro formato: no decodifican y se ignoran.
  const disc = IDL.accounts.find((a: any) => a.name === "Raise").discriminator as number[];
  const raw = await oc.net.conn.getProgramAccounts(oc.programId, {
    filters: [{ memcmp: { offset: 0, bytes: bs58.encode(Uint8Array.from(disc)) } }],
  });
  const all: { publicKey: PublicKey; account: any }[] = [];
  for (const { pubkey, account } of raw) {
    try {
      const dec = oc.program.coder.accounts.decode("raise", account.data);
      if (typeof dec.proposalEvidenceUri !== "string" || dec.floorReserveBps > 5000) continue;
      all.push({ publicKey: pubkey, account: dec });
    } catch {
      /* formato antiguo */
    }
  }
  const rows = await Promise.all(
    all.map(async ({ account }) => {
      const config = new PublicKey(account.dbcConfig);
      const baseMint = new PublicKey(account.baseMint);
      const qm = new PublicKey(account.quoteMint);
      const q = qm.equals(DEFAULT) ? SOL_QUOTE : await quoteOf(oc, qm).catch(() => SOL_QUOTE);
      const r = new Raise(oc, config, baseMint, q.mint, q.program);
      const state = stateName(account.state);
      const bound = !baseMint.equals(DEFAULT);
      const meta = bound ? await tokenMeta(oc.net.conn, baseMint) : { name: "Not launched yet", symbol: "—" };
      let progress: number | null = null;
      if (state === "bonding") {
        try {
          const c = await oc.curve(r);
          progress = Math.min(1, Number(c.reserve.toString()) / Number(c.threshold.toString()));
        } catch {
          progress = 0;
        }
      }
      const treasury = bound ? await oc.tokenBalance(r.treasuryQuote) : new BN(0);
      return {
        config: config.toBase58(),
        ...meta,
        state,
        treasury: Number(treasury.toString()) / 10 ** q.decimals,
        quote: q.symbol,
        progress,
        funded: Number(account.fundedAmount.toString()) / 10 ** q.decimals,
        team: new PublicKey(account.team).toBase58(),
      };
    }),
  );
  const order = ["bonding", "funded", "liquidating", "completed", "pending"];
  return rows.sort((a, b) => order.indexOf(a.state) - order.indexOf(b.state) || b.funded - a.funded);
}

export type Vote = { nonce: number; amount: BN };

export type RaiseDetail = {
  r: Raise;
  raise: any;
  state: string;
  name: string;
  symbol: string;
  team: PublicKey;
  curve: { reserve: BN; threshold: BN; complete: boolean; migrated: boolean } | null;
  cfg: any | null;
  treasuryQuote: BN;
  circulating: BN;
  quote: Quote;
  navPerMillion: number; // moneda que recibe quien redime 1.000.000 tokens
  proposal: { milestone: number; endsAt: number; rejectWeight: BN; quorum: BN; evidenceUri: string; evidenceHash: string } | null;
  /** Lo que el equipo puede cobrar en tramos: financiado − reserva del piso. */
  payable: BN;
  floorReserve: BN;
  floorBudget: BN;
  /** Mercado DAMM v2 tras graduar: precio y respaldo en SOL por 1.000.000 tokens. */
  market: { pricePerMillion: number; backingPerMillion: number; suggest: BN } | null;
  /** Protecciones automáticas (null si el raise es anterior al guard). */
  guard: Awaited<ReturnType<OwnCurve["guardState"]>>;
  budget: Awaited<ReturnType<OwnCurve["budgetState"]>>;
  user: { base: BN; sol: number; quoteBal: BN; votes: Vote[] } | null;
  /** Segundos que el reloj de la cadena va por delante (+) o por detrás (−) del navegador. */
  clockSkew: number;
};

export async function loadRaise(oc: OwnCurve, config: PublicKey, user: PublicKey | null): Promise<RaiseDetail> {
  const raisePda = PublicKey.findProgramAddressSync([Buffer.from("raise"), config.toBuffer()], oc.programId)[0];
  const raise = await (oc.program.account as any).raise.fetch(raisePda);
  const baseMint = new PublicKey(raise.baseMint);
  const cfg0 = await oc.dbc.state.getPoolConfig(config).catch(() => null);
  const qm = new PublicKey(raise.quoteMint);
  const quote = await quoteOf(oc, qm.equals(DEFAULT) ? (cfg0 ? new PublicKey(cfg0.quoteMint) : SOL_QUOTE.mint) : qm);
  const r = new Raise(oc, config, baseMint, quote.mint, quote.program);
  const state = stateName(raise.state);
  const bound = !baseMint.equals(DEFAULT);
  const meta = bound ? await tokenMeta(oc.net.conn, baseMint) : { name: "Not launched yet", symbol: "—" };
  const cfg = cfg0;

  let curve: RaiseDetail["curve"] = null;
  let circulating = new BN(0);
  let treasuryQuote = new BN(0);
  if (bound) {
    const pool = await oc.dbc.state.getPool(r.pool).catch(() => null);
    if (pool && cfg) {
      const p = ps(pool);
      const threshold = new BN(cfg.migrationQuoteThreshold.toString());
      const reserve = new BN(p.quoteReserve.toString());
      curve = { reserve, threshold, complete: reserve.gte(threshold), migrated: Boolean(p.isMigrated) };
    }
    treasuryQuote = await oc.tokenBalance(r.treasuryQuote);
    circulating = (await oc.mintSupply(baseMint)).sub(await oc.tokenBalance(r.treasuryBase));
  }
  const navPerMillion = circulating.isZero()
    ? 0
    : ((Number(treasuryQuote.toString()) / 10 ** quote.decimals) * 1_000_000 * 10 ** BASE_DECIMALS) / Number(circulating.toString());

  const active = raise.milestones.findIndex((m: any) => stateName(m.status) === "proposed");
  const proposal =
    state === "funded" && active >= 0
      ? {
          milestone: active,
          endsAt: Number(raise.proposalEndsAt.toString()),
          rejectWeight: new BN(raise.proposalRejectWeight.toString()),
          quorum: circulating.muln(raise.rejectQuorumBps).divn(10_000),
          evidenceUri: String(raise.proposalEvidenceUri ?? ""),
          evidenceHash: Buffer.from(raise.milestones[active].evidenceHash).toString("hex"),
        }
      : null;

  const funded = new BN(raise.fundedAmount.toString());
  const floorReserve = funded.muln(raise.floorReserveBps).divn(10_000);
  const payable = funded.sub(floorReserve);
  let floorBudget = floorReserve.add(new BN(raise.feesCollected.toString())).sub(new BN(raise.floorSpent.toString()));
  if (floorBudget.isNeg()) floorBudget = new BN(0);
  let market: RaiseDetail["market"] = null;
  if (curve?.migrated) {
    try {
      const st = await oc.dammState(r);
      if (st) {
        // lamports por unidad atómica → SOL por 1.000.000 tokens
        const k = (10 ** BASE_DECIMALS * 1_000_000) / 10 ** quote.decimals;
        const backingUnit = circulating.isZero() ? 0 : Number(treasuryQuote.toString()) / Number(circulating.toString());
        const suggest = ["funded", "completed"].includes(state) ? await oc.suggestDefend(r) : new BN(0);
        market = { pricePerMillion: st.price * k, backingPerMillion: backingUnit * k, suggest };
      }
    } catch {
      /* pool aún no legible */
    }
  }

  const guard = bound ? await oc.guardState(r).catch(() => null) : null;
  const budget = bound ? await oc.budgetState(r).catch(() => null) : null;

  let userInfo: RaiseDetail["user"] = null;
  if (user && bound) {
    const base = await oc.tokenBalance(r.baseAta(user));
    const sol = (await oc.net.conn.getBalance(user)) / LAMPORTS_PER_SOL;
    const nonces = Array.from({ length: Number(raise.proposalNonce) + 1 }, (_, i) => i);
    const infos = await oc.net.conn.getMultipleAccountsInfo(nonces.map((n) => r.voteRecord(user, n)));
    const votes: Vote[] = [];
    infos.forEach((info, i) => {
      if (!info) return;
      const v = oc.program.coder.accounts.decode("voteRecord", info.data);
      votes.push({ nonce: nonces[i], amount: new BN(v.amount.toString()) });
    });
    const quoteBal = r.isSol ? new BN(0) : await oc.tokenBalance(r.quoteAta(user));
    userInfo = { base, sol, quoteBal, votes };
  }

  let clockSkew = 0;
  try {
    const t = await oc.net.conn.getBlockTime(await oc.net.conn.getSlot());
    if (t) clockSkew = t - Math.floor(Date.now() / 1000);
  } catch {
    /* sin hora de la cadena: usamos la del navegador */
  }

  return {
    r,
    raise,
    state,
    clockSkew,
    quote,
    ...meta,
    team: new PublicKey(raise.team),
    curve,
    cfg,
    treasuryQuote,
    circulating,
    navPerMillion,
    proposal,
    payable,
    floorReserve,
    floorBudget,
    market,
    guard,
    budget,
    user: userInfo,
  };
}

/** Lee `fn` al montar y cada `ms` milisegundos; `reload` fuerza una lectura inmediata. */
export function usePoll<T>(fn: () => Promise<T>, deps: unknown[], ms = 6000) {
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<string | null>(null);
  const fnRef = useRef(fn);
  fnRef.current = fn;
  const reload = useCallback(() => {
    fnRef
      .current()
      .then((d) => {
        setData(d);
        setError(null);
      })
      .catch((e) => setError(String(e?.message ?? e)));
  }, []);
  useEffect(() => {
    reload();
    const id = setInterval(reload, ms);
    return () => clearInterval(id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);
  return { data, error, reload };
}
