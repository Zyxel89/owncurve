// F3 · Demo de punta a punta en devnet (o LiteSVM) con dos raises reales:
//
//  A "camino feliz":  lanzar → graduar → harvest → comisiones → migrar a DAMM v2 →
//                     comisiones de LP → venta de pánico → la tesorería defiende el piso
//                     (recompra bajo el respaldo y quema) → 3 tramos con evidencia al equipo
//  B "rechazo":       lanzar → graduar → harvest → el equipo propone → un holder bloquea
//                     con quórum → liquidación → el holder redime sus tokens por SOL
//
// Reanudable: guarda claves y progreso en .owncurve/demo-<cluster>.json.
// Resultado: .owncurve/demo-result-<cluster>.json y docs/DEMO-<cluster>.md (enlaces para jueces).
//
// Uso:  npx tsx scripts/demo.ts            (devnet)
//       CLUSTER=local npx tsx scripts/demo.ts
import { BN } from "@anchor-lang/core";
import { Keypair, LAMPORTS_PER_SOL, PublicKey } from "@solana/web3.js";
import fs from "fs";
import { TxError, loadIdl, makeNet } from "./lib/net";
import { DEFAULT_PARAMS, OwnCurve, Quote, Raise, RaiseParams, evidence, stateName } from "./lib/owncurve";
import { TEST_QUOTES, createTestQuote, devnetFaucet, mintTestQuoteIxs, testQuoteKeypair } from "./lib/quotes";

type Step = { name: string; sig?: string; note?: string };
type RaiseState = { config: number[]; baseMint: number[]; nftMints?: string[]; steps: Step[] };
type DemoState = { version?: number; evidenceBase?: string; programId: string; voter: number[]; a: RaiseState; b: RaiseState; c?: RaiseState; d?: RaiseState; e?: RaiseState; f?: RaiseState; holderE?: number[] };
// v2: piso de precio + evidencia por tramo (las cuentas Raise cambiaron de tamaño)
const DEMO_VERSION = 2;
const EVIDENCE_BASE = process.env.EVIDENCE_BASE ?? "https://github.com/Zyxel89/owncurve";
const MILESTONES = [
  "M1 · on-chain program: treasury, tranches, objections, redemption",
  "M2 · price floor: treasury buys back below backing and burns",
  "M3 · web app + agent skill",
];

const sol = (v: BN | number | bigint) => (Number(v.toString()) / LAMPORTS_PER_SOL).toFixed(4);
const kp = (s: number[]) => Keypair.fromSecretKey(Uint8Array.from(s));
const newRaiseState = (): RaiseState => ({
  config: Array.from(Keypair.generate().secretKey),
  baseMint: Array.from(Keypair.generate().secretKey),
  steps: [],
});

async function main() {
  const net = await makeNet();
  const oc = new OwnCurve(net, loadIdl());
  const payer = net.payer.publicKey;
  const prog = await net.conn.getAccountInfo(oc.programId);
  if (!prog?.executable) throw new Error(`El programa ${oc.programId.toBase58()} no está desplegado en ${net.cluster}`);

  console.log(`\n  Red      : ${net.cluster}`);
  console.log(`  Programa : ${oc.programId.toBase58()}`);
  console.log(`  Wallet   : ${payer.toBase58()} (${sol(await net.conn.getBalance(payer))} SOL)`);

  // ---------------------------------------------------------------- estado reanudable
  const file = `.owncurve/demo-${net.cluster}.json`;
  let st: DemoState | null =
    net.cluster === "devnet" && fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, "utf8")) : null;
  if (st && (st.programId !== oc.programId.toBase58() || st.version !== DEMO_VERSION || st.evidenceBase !== EVIDENCE_BASE)) st = null;
  st ??= {
    version: DEMO_VERSION,
    evidenceBase: EVIDENCE_BASE,
    programId: oc.programId.toBase58(),
    voter: Array.from(Keypair.generate().secretKey),
    a: newRaiseState(),
    b: newRaiseState(),
  };
  st.c ??= newRaiseState();
  st.d ??= newRaiseState();
  st.e ??= newRaiseState();
  st.f ??= newRaiseState();
  st.holderE ??= Array.from(Keypair.generate().secretKey);
  const save = () => {
    fs.mkdirSync(".owncurve", { recursive: true });
    if (net.cluster === "devnet") fs.writeFileSync(file, JSON.stringify(st, null, 2));
  };
  save();

  /** Ejecuta un paso una sola vez (aunque el script se relance) y lo registra. */
  const step = async (rs: RaiseState, name: string, fn: () => Promise<string | void>, note?: () => Promise<string>) => {
    if (rs.steps.some((s) => s.name === name)) {
      console.log(`  · ${name.padEnd(28)} (ya hecho)`);
      return;
    }
    const sig = (await fn()) || undefined;
    const n = note ? await note() : undefined;
    rs.steps.push({ name, sig, note: n });
    save();
    console.log(`  ✔ ${name.padEnd(28)} ${n ?? ""}`);
  };

  /** finalize con reintentos: el reloj de devnet puede ir unos segundos por detrás. */
  const finalizeWhenReady = async (r: Raise) => {
    for (let i = 0; i < 12; i++) {
      try {
        return await oc.finalize(r);
      } catch (e: any) {
        const text = `${e.message}\n${(e.logs ?? []).join("\n")}`;
        if (!/ChallengeWindowOpen/.test(text)) throw e;
        await net.advanceTime(5);
      }
    }
    throw new Error("La ventana de rechazo no cerró a tiempo");
  };

  // ================================================================ RAISE A
  console.log(`\n  ── Raise A · camino feliz ─────────────────────────────`);
  const pA: RaiseParams = { ...DEFAULT_PARAMS, threshold: Number(process.env.THRESHOLD_A ?? 0.5) };
  const A = new Raise(oc, kp(st.a.config).publicKey, kp(st.a.baseMint).publicKey);
  await step(st.a, "A1 crear raise + config DBC", async () => (await oc.createRaise(pA, kp(st!.a.config))).sig);
  await step(st.a, "A2 lanzar pool + bind_pool", async () => (await oc.launchPool(A.config, kp(st!.a.baseMint))).sig);
  await step(st.a, "A3 comprar hasta graduar", async () => (await oc.buyToComplete(A)).at(-1), async () => {
    const c = await oc.curve(A);
    return `reserva ${sol(c.reserve)} SOL`;
  });
  await step(st.a, "A4 harvest", () => oc.harvest(A), async () => `tesorería ${sol((await A.fetch()).fundedAmount)} SOL`);
  await step(st.a, "A5 cobrar comisiones curva", () => oc.collectTradingFees(A), async () => {
    return `+${sol((await A.fetch()).feesCollected)} SOL`;
  });
  await step(st.a, "A6 migrar a DAMM v2", async () => {
    const m = await oc.migrate(A);
    st!.a.nftMints = m.nftMints.map((k) => k.toBase58());
    return m.sig;
  });
  await step(st.a, "A7 swap en DAMM v2", async () => {
    try {
      return await oc.dammBuy(A, new BN(0.02 * LAMPORTS_PER_SOL));
    } catch (e: any) {
      console.log(`    ! swap en DAMM v2 falló (${String(e.message).slice(0, 80)}); se sigue sin comisiones de LP`);
    }
  });
  await step(st.a, "A8 cobrar comisiones de LP", async () => {
    const pos = await oc.treasuryPosition(A, st!.a.nftMints!.map((s) => new PublicKey(s)));
    return oc.claimLpFees(A, pos);
  }, async () => `fees totales ${sol((await A.fetch()).feesCollected)} SOL`);

  // Piso de precio: alguien vende fuerte en DAMM v2 y el precio cae bajo el respaldo
  let floorNote = "";
  await step(st.a, "A8b venta de pánico en DAMM v2", async () => {
    const mine = await oc.tokenBalance(A.baseAta(payer));
    return oc.dammSell(A, mine.muln(6).divn(10));
  }, async () => {
    const s = await oc.dammState(A);
    const b = await oc.backing(A);
    return `precio ${(s!.price * 1e3).toPrecision(3)} vs respaldo ${(b.perUnit * 1e3).toPrecision(3)} SOL/M tokens`;
  });
  await step(st.a, "A8c defend_floor", async () => {
    const amount = await oc.suggestDefend(A);
    if (amount.isZero()) {
      floorNote = "precio ya sobre el respaldo";
      return;
    }
    const before = (await oc.backing(A)).perUnit;
    const sig = await oc.defendFloor(A, amount);
    const after = (await oc.backing(A)).perUnit;
    const raise = await A.fetch();
    const burned = Number(raise.tokensBurned.toString()) / 1e6;
    floorNote = `recompró ${sol(raise.floorSpent)} SOL, quemó ${burned.toLocaleString("en-US", { maximumFractionDigits: 0 })} tokens, respaldo +${(((after - before) / before) * 100).toFixed(0)}%`;
    return sig;
  }, async () => floorNote);
  for (let i = 1; i <= pA.tranchesBps.length; i++) {
    await step(st.a, `A9.${i} proponer tramo ${i}`, async () => {
      const raise = await A.fetch();
      const active = raise.milestones.some((m: any) => stateName(m.status) === "proposed");
      if (!active)
        return oc.propose(A, undefined, await evidence(`${EVIDENCE_BASE}/blob/main/docs/MILESTONES.md#m${i}`, MILESTONES[i - 1]));
    });
    await step(st.a, `A9.${i} esperar ventana (${pA.challengeSecs}s)`, async () => net.advanceTime(pA.challengeSecs));
    await step(st.a, `A9.${i} finalizar tramo ${i}`, () => finalizeWhenReady(A), async () => {
      const raise = await A.fetch();
      const payable = new BN(raise.fundedAmount.toString()).muln(10_000 - raise.floorReserveBps).divn(10_000);
      return `liberado ${sol(raise.releasedAmount)} / ${sol(payable)} SOL`;
    });
  }
  const finalA = await A.fetch();

  // ================================================================ RAISE B
  console.log(`\n  ── Raise B · rechazo y liquidación ─────────────────────`);
  const pB: RaiseParams = { ...DEFAULT_PARAMS, threshold: Number(process.env.THRESHOLD_B ?? 0.3) };
  const B = new Raise(oc, kp(st.b.config).publicKey, kp(st.b.baseMint).publicKey);
  const voter = kp(st.voter);
  await step(st.b, "B1 crear raise + config DBC", async () => (await oc.createRaise(pB, kp(st!.b.config))).sig);
  await step(st.b, "B2 lanzar pool + bind_pool", async () => (await oc.launchPool(B.config, kp(st!.b.baseMint))).sig);
  await step(st.b, "B3 comprar hasta graduar", async () => (await oc.buyToComplete(B)).at(-1));
  await step(st.b, "B4 harvest", () => oc.harvest(B), async () => `tesorería ${sol((await B.fetch()).fundedAmount)} SOL`);
  await step(st.b, "B5 fondear al holder", () => net.fund(voter.publicKey, 0.03 * LAMPORTS_PER_SOL));
  await step(st.b, "B6 holder recibe 15% del suministro", async () => {
    const circ = (await oc.mintSupply(B.baseMint)).sub(await oc.tokenBalance(B.treasuryBase));
    return oc.transferBase(B, net.payer, voter.publicKey, circ.muln(1500).divn(10_000));
  });
  await step(st.b, "B7 equipo propone tramo 1", () => oc.propose(B));
  await step(st.b, "B8 holder vota rechazo", async () => {
    const bal = await oc.tokenBalance(B.baseAta(voter.publicKey));
    return oc.reject(B, voter, bal);
  }, async () => `bloqueados ${(await B.fetch()).proposalRejectWeight.toString()} tokens (base units)`);
  await step(st.b, `B9 esperar ventana (${pB.challengeSecs}s)`, async () => net.advanceTime(pB.challengeSecs));
  await step(st.b, "B10 finalizar → liquidación", () => finalizeWhenReady(B), async () => `estado "${await B.state()}"`);
  await step(st.b, "B11 holder retira su voto", () => oc.withdrawVote(B, voter, 0));
  let redeemPaid = new BN(0);
  await step(st.b, "B12 holder redime por SOL", async () => {
    const amount = await oc.tokenBalance(B.baseAta(voter.publicKey));
    const before = await oc.tokenBalance(B.quoteAta(voter.publicKey));
    const sig = await oc.redeem(B, voter, amount);
    redeemPaid = (await oc.tokenBalance(B.quoteAta(voter.publicKey))).sub(before);
    return sig;
  }, async () => `recibió ${sol(redeemPaid)} SOL (wSOL) por sus tokens`);
  const finalB = await B.fetch();

  // ================================================================ RAISES C y D: otras monedas
  // Monedas de prueba con la misma dirección en todas partes; en mainnet serían USDC y una xStock.
  const [usdSpec, stockSpec] = TEST_QUOTES;
  const faucet = devnetFaucet();
  const ensureQuote = async (spec: typeof usdSpec, amount: number): Promise<Quote> => {
    const q = await createTestQuote(net, spec, testQuoteKeypair(spec.symbol), faucet.publicKey);
    const have = await oc.tokenBalance(new Raise(oc, PublicKey.default, PublicKey.default, q.mint, q.program).quoteAta(payer));
    if (have.lt(new BN(amount).mul(new BN(10).pow(new BN(q.decimals)))))
      await net.send(`emitir ${spec.symbol}`, mintTestQuoteIxs(q, faucet.publicKey, payer, payer, amount * 2), [faucet]);
    return q;
  };

  console.log(`\n  ── Raise C · recaudado en ${usdSpec.symbol} (como USDC) ───────────────`);
  const usd = await ensureQuote(usdSpec, 150);
  const pC: RaiseParams = { ...DEFAULT_PARAMS, threshold: 100, quote: usd };
  const C = new Raise(oc, kp(st.c!.config).publicKey, kp(st.c!.baseMint).publicKey, usd.mint, usd.program);
  const qsol = (q: Quote) => (v: any) => (Number(v.toString()) / 10 ** q.decimals).toFixed(2);
  const usdFmt = qsol(usd);
  await step(st.c!, "C1 crear raise en tUSD", async () => (await oc.createRaise(pC, kp(st!.c!.config))).sig);
  await step(st.c!, "C2 lanzar pool + bind_pool", async () => (await oc.launchPool(C.config, kp(st!.c!.baseMint), undefined, true, { name: "Harbor Coop", symbol: "HBR", uri: "https://raw.githubusercontent.com/solana-developers/opos-asset/main/assets/DeveloperPortal/metadata.json" })).sig);
  await step(st.c!, "C3 comprar hasta graduar", async () => (await oc.buyToComplete(C)).at(-1));
  await step(st.c!, "C4 harvest", () => oc.harvest(C), async () => `tesorería ${usdFmt((await C.fetch()).fundedAmount)} tUSD`);
  await step(st.c!, "C5 migrar a DAMM v2", async () => (await oc.migrate(C)).sig);
  await step(st.c!, "C6 proponer tramo 1", async () => {
    const raise = await C.fetch();
    if (!raise.milestones.some((m: any) => stateName(m.status) === "proposed"))
      return oc.propose(C, undefined, await evidence(`${EVIDENCE_BASE}/blob/main/docs/MILESTONES.md#m1`, MILESTONES[0]));
  });
  await step(st.c!, `C7 esperar ventana (${pC.challengeSecs}s)`, async () => net.advanceTime(pC.challengeSecs));
  await step(st.c!, "C8 finalizar tramo 1", () => finalizeWhenReady(C), async () => `liberado ${usdFmt((await C.fetch()).releasedAmount)} tUSD`);
  const finalC = await C.fetch();

  console.log(`\n  ── Raise D · recaudado en ${stockSpec.symbol} (Token-2022, como una xStock) ──`);
  const stock = await ensureQuote(stockSpec, 2);
  const pD: RaiseParams = { ...DEFAULT_PARAMS, threshold: 1, quote: stock };
  const D = new Raise(oc, kp(st.d!.config).publicKey, kp(st.d!.baseMint).publicKey, stock.mint, stock.program);
  const stockFmt = (v: any) => (Number(v.toString()) / 10 ** stock.decimals).toFixed(4);
  await step(st.d!, "D1 crear raise en tNVDAx", async () => (await oc.createRaise(pD, kp(st!.d!.config))).sig);
  await step(st.d!, "D2 lanzar pool + bind_pool", async () => (await oc.launchPool(D.config, kp(st!.d!.baseMint), undefined, true, { name: "Atlas Robotics", symbol: "ATLS", uri: "https://raw.githubusercontent.com/solana-developers/opos-asset/main/assets/DeveloperPortal/metadata.json" })).sig);
  await step(st.d!, "D3 comprar hasta graduar", async () => (await oc.buyToComplete(D)).at(-1));
  await step(st.d!, "D4 harvest", () => oc.harvest(D), async () => `tesorería ${stockFmt((await D.fetch()).fundedAmount)} tNVDAx`);
  await step(st.d!, "D5 migrar a DAMM v2", async () => (await oc.migrate(D)).sig);
  await step(st.d!, "D6 venta de pánico en DAMM v2", async () => {
    const mine = await oc.tokenBalance(D.baseAta(payer));
    return oc.dammSell(D, mine.muln(6).divn(10));
  });
  let floorD = "";
  await step(st.d!, "D7 defend_floor", async () => {
    const amount = await oc.suggestDefend(D);
    if (amount.isZero()) {
      floorD = "precio ya sobre el respaldo";
      return;
    }
    const before = (await oc.backing(D)).perUnit;
    const sig = await oc.defendFloor(D, amount);
    const after = (await oc.backing(D)).perUnit;
    floorD = `recompró ${stockFmt(amount)} tNVDAx, respaldo +${(((after - before) / before) * 100).toFixed(0)}%`;
    return sig;
  }, async () => floorD);
  const finalD = await D.fetch();

  /** Reintenta mientras el reloj de devnet no haya llegado (ventanas e intervalos del guard). */
  const whenReady = async (fn: () => Promise<string>, errName: RegExp, step = 5) => {
    for (let i = 0; i < 20; i++) {
      try {
        return await fn();
      } catch (e: any) {
        const text = `${e.message}\n${(e.logs ?? []).join("\n")}`;
        if (!errName.test(text)) throw e;
        await net.advanceTime(step);
      }
    }
    throw new Error("El reloj de la red no avanzó a tiempo");
  };

  // ================================================================ RAISE E: Bedrock en cadena
  console.log(`\n  ── Raise E · cláusula Bedrock en cadena (TWAP + oferta pública) ──`);
  const pE: RaiseParams = { ...DEFAULT_PARAMS, threshold: 0.25 };
  const E = new Raise(oc, kp(st.e!.config).publicKey, kp(st.e!.baseMint).publicKey);
  const holderE = kp(st.holderE!);
  let twapNote = "";
  await step(st.e!, "E1 crear raise con guard", async () => (await oc.createRaise(pE, kp(st!.e!.config))).sig);
  await step(st.e!, "E2 lanzar pool + bind_pool", async () => (await oc.launchPool(E.config, kp(st!.e!.baseMint), undefined, true, { name: "Keystone Studio", symbol: "KEY", uri: "https://raw.githubusercontent.com/solana-developers/opos-asset/main/assets/DeveloperPortal/metadata.json" })).sig);
  await step(st.e!, "E3 comprar hasta graduar", async () => (await oc.buyToComplete(E)).at(-1));
  await step(st.e!, "E4 harvest + arm_guard", () => oc.harvest(E), async () => `tesorería ${sol((await E.fetch()).fundedAmount)} SOL`);
  await step(st.e!, "E5 migrar a DAMM v2", async () => (await oc.migrate(E)).sig);
  await step(st.e!, "E6 holder recibe 5% del suministro", async () => {
    await net.fund(holderE.publicKey, 0.02 * LAMPORTS_PER_SOL);
    const circ = (await oc.mintSupply(E.baseMint)).sub(await oc.tokenBalance(E.treasuryBase));
    return oc.transferBase(E, net.payer, holderE.publicKey, circ.muln(500).divn(10_000));
  });
  const gE = (await oc.guardState(E))!;
  for (let i = 1; i <= 5; i++) {
    await step(st.e!, `E7.${i} observe (TWAP)`, async () => {
      if (i > 1) await net.advanceTime(gE.observeIntervalSecs);
      return whenReady(() => oc.observe(E), /ObservationTooSoon/);
    });
  }
  await step(st.e!, "E8 oferta pública (tender_offer)", async () => {
    const g = await oc.guardState(E);
    if (!g!.twapReady) await net.advanceTime(gE.observeIntervalSecs);
    const g2 = (await oc.guardState(E))!;
    twapNote = `TWAP ${(g2.twap * 1e3).toPrecision(3)} → oferta ${(g2.buyoutPrice * 1e3).toPrecision(3)} SOL/M tokens (+${g2.buyoutPremiumBps / 100}%), depósito ${sol(g2.buyoutDeposit)} SOL`;
    return whenReady(() => oc.tenderOffer(E, g2.buyoutDeposit.muln(105).divn(100).addn(1_000_000)), /TwapNotReady/);
  }, async () => twapNote);
  let paidE = "";
  await step(st.e!, "E9 holder redime a precio de oferta", async () => {
    const amount = await oc.tokenBalance(E.baseAta(holderE.publicKey));
    const sig = await oc.redeem(E, holderE, amount);
    const got = await oc.tokenBalance(E.quoteAta(holderE.publicKey));
    const g = (await oc.guardState(E))!;
    const perToken = Number(got.toString()) / Number(amount.toString());
    paidE = `cobró ${sol(got)} SOL: ${((perToken / g.twap - 1) * 100).toFixed(0)}% sobre el TWAP`;
    return sig;
  }, async () => paidE);
  await step(st.e!, "E10 el comprador redime sus tokens", async () => {
    const amount = await oc.tokenBalance(E.baseAta(payer));
    if (amount.gtn(0)) return oc.redeem(E, net.payer, amount);
  });
  const finalE = await E.fetch();

  // ================================================================ RAISE F: equipo fantasma
  console.log(`\n  ── Raise F · equipo fantasma: la tesorería vuelve a los holders ──`);
  const pF: RaiseParams = { ...DEFAULT_PARAMS, threshold: 0.1, guard: { inactivitySecs: 60, buyoutPremiumBps: 3000, twapWindowSecs: 120 } };
  const F = new Raise(oc, kp(st.f!.config).publicKey, kp(st.f!.baseMint).publicKey);
  await step(st.f!, "F1 crear raise con guard (60 s)", async () => (await oc.createRaise(pF, kp(st!.f!.config))).sig);
  await step(st.f!, "F2 lanzar pool + bind_pool", async () => (await oc.launchPool(F.config, kp(st!.f!.baseMint), undefined, true, { name: "Driftwood Games", symbol: "DRFT", uri: "https://raw.githubusercontent.com/solana-developers/opos-asset/main/assets/DeveloperPortal/metadata.json" })).sig);
  await step(st.f!, "F3 comprar hasta graduar", async () => (await oc.buyToComplete(F)).at(-1));
  await step(st.f!, "F4 harvest + arm_guard", () => oc.harvest(F), async () => `tesorería ${sol((await F.fetch()).fundedAmount)} SOL`);
  await step(st.f!, "F5 el equipo no pide nada en 60 s", async () => net.advanceTime(60));
  await step(st.f!, "F6 declare_abandoned", () => whenReady(() => oc.declareAbandoned(F), /TeamStillActive/), async () => `estado "${await F.state()}"`);
  const finalF = await F.fetch();

  // ================================================================ resumen
  const link = (s?: string) => (s ? net.explorer(s) : "");
  const addr = (a: PublicKey) =>
    net.cluster === "devnet" ? `https://explorer.solana.com/address/${a.toBase58()}?cluster=devnet` : a.toBase58();
  const result = {
    cluster: net.cluster,
    programId: oc.programId.toBase58(),
    raiseA: {
      config: A.config.toBase58(),
      treasury: A.treasury.toBase58(),
      state: stateName(finalA.state),
      fundedSol: sol(finalA.fundedAmount),
      releasedSol: sol(finalA.releasedAmount),
      payableSol: sol(new BN(finalA.fundedAmount.toString()).muln(10_000 - finalA.floorReserveBps).divn(10_000)),
      feesSol: sol(finalA.feesCollected),
      floorSpentSol: sol(finalA.floorSpent),
      tokensBurned: finalA.tokensBurned.toString(),
      treasuryNowSol: sol(await oc.tokenBalance(A.treasuryQuote)),
      steps: st.a.steps.map((s) => ({ ...s, link: link(s.sig) })),
    },
    raiseB: {
      config: B.config.toBase58(),
      treasury: B.treasury.toBase58(),
      state: stateName(finalB.state),
      fundedSol: sol(finalB.fundedAmount),
      steps: st.b.steps.map((s) => ({ ...s, link: link(s.sig) })),
    },
    raiseC: {
      config: C.config.toBase58(),
      treasury: C.treasury.toBase58(),
      quote: { symbol: usd.symbol, mint: usd.mint.toBase58() },
      state: stateName(finalC.state),
      funded: usdFmt(finalC.fundedAmount),
      released: usdFmt(finalC.releasedAmount),
      steps: st.c!.steps.map((s) => ({ ...s, link: link(s.sig) })),
    },
    raiseD: {
      config: D.config.toBase58(),
      treasury: D.treasury.toBase58(),
      quote: { symbol: stock.symbol, mint: stock.mint.toBase58() },
      state: stateName(finalD.state),
      funded: stockFmt(finalD.fundedAmount),
      floorSpent: stockFmt(finalD.floorSpent),
      tokensBurned: finalD.tokensBurned.toString(),
      steps: st.d!.steps.map((s) => ({ ...s, link: link(s.sig) })),
    },
    raiseE: {
      config: E.config.toBase58(),
      treasury: E.treasury.toBase58(),
      state: stateName(finalE.state),
      acquirer: new PublicKey(finalE.team).toBase58(),
      note: twapNote,
      steps: st.e!.steps.map((s) => ({ ...s, link: link(s.sig) })),
    },
    raiseF: {
      config: F.config.toBase58(),
      treasury: F.treasury.toBase58(),
      state: stateName(finalF.state),
      fundedSol: sol(finalF.fundedAmount),
      steps: st.f!.steps.map((s) => ({ ...s, link: link(s.sig) })),
    },
  };
  fs.writeFileSync(`.owncurve/demo-result-${net.cluster}.json`, JSON.stringify(result, null, 2));

  // Informe para jueces, en inglés (los pasos internos conservan su nombre para poder reanudar).
  const EN: [RegExp, string][] = [
    [/crear raise \+ config DBC/, "init_raise + DBC create_config"],
    [/crear raise en (\w+)/, "init_raise + DBC create_config (raised in $1)"],
    [/lanzar pool \+ bind_pool/, "DBC create_pool + bind_pool (on-chain checks)"],
    [/comprar hasta graduar/, "buy until the curve graduates"],
    [/cobrar comisiones curva/, "collect curve trading fees (CPI)"],
    [/migrar a DAMM v2/, "migrate to DAMM v2"],
    [/swap en DAMM v2/, "swap on DAMM v2"],
    [/cobrar comisiones de LP/, "claim LP fees of the treasury position (CPI)"],
    [/venta de pánico en DAMM v2/, "panic sell on DAMM v2"],
    [/proponer tramo (\d)/, "propose tranche $1 with evidence"],
    [/esperar ventana \((\d+)s\)/, "wait for the $1 s objection window"],
    [/finalizar tramo (\d)/, "settle tranche $1"],
    [/fondear al holder/, "fund the holder"],
    [/holder recibe 15% del suministro/, "holder receives 15% of supply"],
    [/equipo propone tramo 1/, "team proposes tranche 1"],
    [/holder vota rechazo/, "holder objects (locks tokens)"],
    [/finalizar → liquidación/, "settle → liquidation"],
    [/holder retira su voto/, "holder unlocks voted tokens"],
    [/holder redime por SOL/, "holder redeems tokens for SOL"],
    [/tesorería/g, "treasury"],
    [/reserva/g, "reserve"],
    [/fees totales/g, "total fees"],
    [/liberado/g, "released"],
    [/precio/g, "price"],
    [/respaldo/g, "backing"],
    [/recompró/g, "bought back"],
    [/quemó/g, "burned"],
    [/bloqueados/g, "locked"],
    [/estado/g, "state"],
    [/recibió (.*) por sus tokens/, "received $1 for the tokens"],
    [/SOL\/M tokens/g, "SOL per 1M tokens"],
    [/crear raise con guard \((\d+) s\)/, "init_raise + init_guard ($1 s inactivity) + DBC create_config"],
    [/crear raise con guard/, "init_raise + init_guard + DBC create_config"],
    [/harvest \+ arm_guard/, "harvest + arm_guard (inactivity clock starts)"],
    [/holder recibe 5% del suministro/, "holder receives 5% of supply"],
    [/observe \(TWAP\)/, "observe: record the DAMM v2 price for the TWAP"],
    [/oferta pública \(tender_offer\)/, "tender_offer: takeover paying every holder TWAP +30%"],
    [/holder redime a precio de oferta/, "holder redeems at the buyout price"],
    [/el comprador redime sus tokens/, "acquirer redeems its own tokens"],
    [/el equipo no pide nada en (\d+) s/, "team stays silent for $1 s"],
    [/oferta/g, "offer"],
    [/depósito/g, "deposit"],
    [/cobró (.*): (.*)% sobre el TWAP/, "received $1: $2% above the TWAP"],
  ];
  const en = (t = "") => EN.reduce((acc, [re, rep]) => acc.replace(re, rep), t);
  const table = (steps: { name: string; note?: string; link: string; sig?: string }[]) => [
    `| Step | Result | Transaction |`,
    `| --- | --- | --- |`,
    ...steps.filter((s) => s.sig).map((s) => `| ${en(s.name)} | ${en(s.note)} | [view](${s.link}) |`),
  ];
  const md = [
    `# OwnCurve · ${net.cluster} demo`,
    ``,
    `Program: [\`${oc.programId.toBase58()}\`](${addr(oc.programId)}) · every transaction below is real and links to the explorer.`,
    ``,
    `## Raise A · tranches with evidence + price floor (SOL)`,
    ``,
    `Treasury [\`${A.treasury.toBase58()}\`](${addr(A.treasury)}) · funded ${result.raiseA.fundedSol} SOL · paid to the team in 3 evidence-backed tranches ${result.raiseA.releasedSol} SOL (all of the payable ${result.raiseA.payableSol}) · fees collected ${result.raiseA.feesSol} SOL · floor defense ${result.raiseA.floorSpentSol} SOL · the treasury still holds ${result.raiseA.treasuryNowSol} SOL of backing for holders · final state **${result.raiseA.state}**.`,
    ``,
    ...table(result.raiseA.steps),
    ``,
    `## Raise B · holders stop a tranche → liquidation → redemption (SOL)`,
    ``,
    `Treasury [\`${B.treasury.toBase58()}\`](${addr(B.treasury)}) · funded ${result.raiseB.fundedSol} SOL · final state **${result.raiseB.state}**: the team got nothing and holders redeem against the treasury.`,
    ``,
    ...table(result.raiseB.steps),
    ``,
    `## Raise C · raised in a stablecoin (${usd.symbol}, SPL token like USDC)`,
    ``,
    `Currency [\`${usd.mint.toBase58()}\`](${addr(usd.mint)}) (devnet test token) · treasury [\`${C.treasury.toBase58()}\`](${addr(C.treasury)}) · funded ${result.raiseC.funded} ${usd.symbol} · tranche 1 paid ${result.raiseC.released} ${usd.symbol}.`,
    ``,
    ...table(result.raiseC.steps),
    ``,
    `## Raise D · raised in a tokenized stock (${stock.symbol}, Token-2022 like xStocks)`,
    ``,
    `Currency [\`${stock.mint.toBase58()}\`](${addr(stock.mint)}) (devnet test token) · treasury [\`${D.treasury.toBase58()}\`](${addr(D.treasury)}) · funded ${result.raiseD.funded} ${stock.symbol} · floor defense ${result.raiseD.floorSpent} ${stock.symbol}.`,
    ``,
    ...table(result.raiseD.steps),
    ``,
    `## Raise E · Meteora Bedrock's takeover clause, enforced on-chain`,
    ``,
    `Treasury [\`${E.treasury.toBase58()}\`](${addr(E.treasury)}) · the program built its own TWAP from DAMM v2 price observations; a takeover had to top the treasury up so every holder redeems at TWAP +30%. ${en(result.raiseE.note)} · final state **${result.raiseE.state}**, new team ${result.raiseE.acquirer.slice(0, 6)}….`,
    ``,
    ...table(result.raiseE.steps),
    ``,
    `## Raise F · the team went silent, the treasury went back to holders`,
    ``,
    `Treasury [\`${F.treasury.toBase58()}\`](${addr(F.treasury)}) · funded ${result.raiseF.fundedSol} SOL · no tranche request within the guard's window (60 s on devnet), so anyone could call \`declare_abandoned\` · final state **${result.raiseF.state}**.`,
    ``,
    ...table(result.raiseF.steps),
    ``,
  ].join("\n");
  fs.mkdirSync("docs", { recursive: true });
  fs.writeFileSync(`docs/DEMO-${net.cluster}.md`, md);

  const okA = result.raiseA.state === "completed" && result.raiseA.releasedSol === result.raiseA.payableSol;
  const okB = result.raiseB.state === "liquidating";
  const okC = Number(result.raiseC.released) > 0;
  const okD = ["funded", "completed"].includes(result.raiseD.state);
  const okE = result.raiseE.state === "liquidating";
  const okF = result.raiseF.state === "liquidating";
  if (!okA || !okB || !okC || !okD || !okE || !okF)
    throw new Error(`Demo incompleta: A=${result.raiseA.state} B=${result.raiseB.state} C=${result.raiseC.released} D=${result.raiseD.state} E=${result.raiseE.state} F=${result.raiseF.state}`);
  console.log(`\n  DEMO OK: ciclo completo en ${net.cluster} (A completado con piso defendido, B en liquidación, C en tUSD, D en tNVDAx, E comprado con prima, F devuelto por abandono).`);
  console.log(`  Resumen para jueces: docs/DEMO-${net.cluster}.md`);
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error(`\n  ✘ ${e.message ?? e}`);
    if (e instanceof TxError && e.logs) {
      console.error("  Logs del programa (últimas 25 líneas):");
      for (const l of e.logs.slice(-25)) console.error("    " + l);
    }
    console.error("  Vuelve a ejecutar: el demo retoma desde el último paso completado.");
    process.exit(1);
  });
