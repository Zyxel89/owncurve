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
import { DEFAULT_PARAMS, OwnCurve, Raise, RaiseParams, evidence, stateName } from "./lib/owncurve";

type Step = { name: string; sig?: string; note?: string };
type RaiseState = { config: number[]; baseMint: number[]; nftMints?: string[]; steps: Step[] };
type DemoState = { version?: number; programId: string; voter: number[]; a: RaiseState; b: RaiseState };
// v2: piso de precio + evidencia por tramo (las cuentas Raise cambiaron de tamaño)
const DEMO_VERSION = 2;
const EVIDENCE_BASE = process.env.EVIDENCE_BASE ?? "https://github.com/owncurve/owncurve";
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
  if (st && (st.programId !== oc.programId.toBase58() || st.version !== DEMO_VERSION)) st = null;
  st ??= {
    version: DEMO_VERSION,
    programId: oc.programId.toBase58(),
    voter: Array.from(Keypair.generate().secretKey),
    a: newRaiseState(),
    b: newRaiseState(),
  };
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
  const pA: RaiseParams = { ...DEFAULT_PARAMS, thresholdSol: Number(process.env.THRESHOLD_A ?? 0.5) };
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
  const pB: RaiseParams = { ...DEFAULT_PARAMS, thresholdSol: Number(process.env.THRESHOLD_B ?? 0.3) };
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
  };
  fs.writeFileSync(`.owncurve/demo-result-${net.cluster}.json`, JSON.stringify(result, null, 2));

  const md = [
    `# OwnCurve · demo en ${net.cluster}`,
    ``,
    `Programa: [\`${oc.programId.toBase58()}\`](${addr(oc.programId)})`,
    ``,
    `## Raise A · camino feliz`,
    ``,
    `Tesorería [\`${A.treasury.toBase58()}\`](${addr(A.treasury)}) · financiado ${result.raiseA.fundedSol} SOL · liberado al equipo en 3 tramos con evidencia ${result.raiseA.releasedSol} SOL (todo lo cobrable: ${result.raiseA.payableSol}) · comisiones cobradas ${result.raiseA.feesSol} SOL · defensa del piso ${result.raiseA.floorSpentSol} SOL · la tesorería conserva ${result.raiseA.treasuryNowSol} SOL de respaldo para los holders · estado final **${result.raiseA.state}**.`,
    ``,
    `| Paso | Resultado | Transacción |`,
    `| --- | --- | --- |`,
    ...result.raiseA.steps.filter((s) => s.sig).map((s) => `| ${s.name} | ${s.note ?? ""} | [ver](${s.link}) |`),
    ``,
    `## Raise B · rechazo y liquidación`,
    ``,
    `Tesorería [\`${B.treasury.toBase58()}\`](${addr(B.treasury)}) · financiado ${result.raiseB.fundedSol} SOL · estado final **${result.raiseB.state}**: el equipo no cobró nada y los holders redimen contra la tesorería.`,
    ``,
    `| Paso | Resultado | Transacción |`,
    `| --- | --- | --- |`,
    ...result.raiseB.steps.filter((s) => s.sig).map((s) => `| ${s.name} | ${s.note ?? ""} | [ver](${s.link}) |`),
    ``,
  ].join("\n");
  fs.mkdirSync("docs", { recursive: true });
  fs.writeFileSync(`docs/DEMO-${net.cluster}.md`, md);

  const okA = result.raiseA.state === "completed" && result.raiseA.releasedSol === result.raiseA.payableSol;
  const okB = result.raiseB.state === "liquidating";
  if (!okA || !okB) throw new Error(`Demo incompleta: A=${result.raiseA.state} B=${result.raiseB.state}`);
  console.log(`\n  DEMO OK: ciclo completo en ${net.cluster} (A completado con piso defendido, B en liquidación).`);
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
