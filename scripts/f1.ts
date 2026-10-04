// F1 · Validación técnica de OwnCurve sobre Meteora DBC (devnet o LiteSVM).
//
//  1. init_raise + DBC create_config en UNA transacción (fee_claimer y leftover = tesorería PDA)
//  2. DBC create_pool + bind_pool en UNA transacción (el launch nace validado)
//  3. Compras hasta completar la curva
//  4. harvest: CPI withdraw_migration_fee firmada por la PDA → la tesorería recibe el 80%
//  5. (--migrate) migración a DAMM v2
//
// Reanudable en devnet: guarda claves y progreso en .owncurve/f1-devnet.json.
// Uso:  npx tsx scripts/f1.ts --migrate            (devnet)
//       CLUSTER=local npx tsx scripts/f1.ts --migrate   (LiteSVM con los .so reales)
import { BN } from "@anchor-lang/core";
import { Keypair, LAMPORTS_PER_SOL, PublicKey } from "@solana/web3.js";
import fs from "fs";
import { DEFAULT_PARAMS, OwnCurve, Raise, ps, stateName } from "./lib/owncurve";
import { TxError, loadIdl, makeNet } from "./lib/net";

const DO_MIGRATE = process.argv.includes("--migrate");
const PARAMS = { ...DEFAULT_PARAMS, threshold: Number(process.env.THRESHOLD_SOL ?? DEFAULT_PARAMS.threshold) };

type State = { programId: string; config: number[]; baseMint: number[]; sigs: Record<string, string> };

const log = (step: string, msg: string) => console.log(`  ✔ ${step.padEnd(12)} ${msg}`);
const sol = (v: number | bigint | BN) => (Number(v.toString()) / LAMPORTS_PER_SOL).toFixed(4);
const kp = (s: number[]) => Keypair.fromSecretKey(Uint8Array.from(s));

async function main() {
  const net = await makeNet();
  const oc = new OwnCurve(net, loadIdl());
  const payer = net.payer.publicKey;

  console.log(`\n  Red        : ${net.cluster}`);
  console.log(`  Programa   : ${oc.programId.toBase58()}`);
  console.log(`  Wallet     : ${payer.toBase58()} (${sol(await net.conn.getBalance(payer))} SOL)`);
  const prog = await net.conn.getAccountInfo(oc.programId);
  if (!prog?.executable) throw new Error(`El programa ${oc.programId.toBase58()} no está desplegado en ${net.cluster}`);

  // ------------------------------------------------------------ estado reanudable
  const stateFile = `.owncurve/f1-${net.cluster}.json`;
  let st: State | null = null;
  if (net.cluster === "devnet" && fs.existsSync(stateFile)) {
    st = JSON.parse(fs.readFileSync(stateFile, "utf8"));
    if (st!.programId !== oc.programId.toBase58()) st = null;
  }
  st ??= {
    programId: oc.programId.toBase58(),
    config: Array.from(Keypair.generate().secretKey),
    baseMint: Array.from(Keypair.generate().secretKey),
    sigs: {},
  };
  const save = () => {
    if (net.cluster !== "devnet") return;
    fs.mkdirSync(".owncurve", { recursive: true });
    fs.writeFileSync(stateFile, JSON.stringify(st, null, 2));
  };
  save();

  const configKp = kp(st.config);
  const baseMintKp = kp(st.baseMint);
  const r = new Raise(oc, configKp.publicKey, baseMintKp.publicKey);
  console.log(`  Config DBC : ${r.config.toBase58()}`);
  console.log(`  Tesorería  : ${r.treasury.toBase58()}\n`);

  // F1.2 raise + config DBC (atómico)
  if (!(await r.fetchNullable())) {
    st.sigs.raise = (await oc.createRaise(PARAMS, configKp)).sig;
    save();
  }
  const cfg = await oc.dbc.state.getPoolConfig(r.config);
  if (!cfg || !new PublicKey(cfg.feeClaimer).equals(r.treasury)) throw new Error("fee_claimer no es la tesorería");
  log("F1.2 config", `fee_claimer = tesorería · migration fee ${cfg.migrationFeePercentage}% · umbral ${sol(cfg.migrationQuoteThreshold)} SOL`);

  // F1.3 pool + bind_pool (atómico) y compras
  if ((await r.state()) === "pending") {
    st.sigs.pool = (await oc.launchPool(r.config, baseMintKp)).sig;
    save();
  }
  log("F1.3 pool", `${r.pool.toBase58()} · raise en estado "${await r.state()}"`);
  const buys = await oc.buyToComplete(r);
  buys.forEach((s, i) => (st!.sigs[`buy${i}`] = s));
  save();
  const c = await oc.curve(r);
  log("F1.3 curva", `completa · reserva ${sol(c.reserve)} SOL ≥ umbral ${sol(c.threshold)} SOL`);

  // F1.5 harvest
  if ((await r.state()) === "bonding") {
    st.sigs.harvest = await oc.harvest(r);
    save();
  }
  const raise = await r.fetch();
  const funded = new BN(raise.fundedAmount.toString());
  const expected = c.threshold.muln(PARAMS.treasuryPct).divn(100);
  if (stateName(raise.state) !== "funded" || !funded.eq(expected)) {
    throw new Error(`harvest no cuadra: estado=${stateName(raise.state)} funded=${funded} esperado=${expected}`);
  }
  log("F1.5 harvest", `tesorería = ${sol(funded)} SOL (${PARAMS.treasuryPct}% de ${sol(c.threshold)}) · estado "funded"`);

  // F1.4 migración (opcional)
  let migrated = Boolean(ps(await oc.dbc.state.getPool(r.pool)).isMigrated);
  if (DO_MIGRATE && !migrated) {
    try {
      st.sigs.migrate = (await oc.migrate(r)).sig;
      save();
      migrated = true;
    } catch (e: any) {
      console.log(`  ! F1.4 migración: falló (${String(e.message).slice(0, 120)})`);
      if (e instanceof TxError && e.logs) for (const l of e.logs.slice(-15)) console.log("      " + l);
      console.log(`    No bloquea F1. Alternativa: https://migrator.meteora.ag  con el pool ${r.pool.toBase58()}`);
    }
  }
  if (migrated) log("F1.4 migrar", "pool graduado a DAMM v2");
  else if (!DO_MIGRATE) console.log("  · F1.4 migrar  pendiente (ejecuta con --migrate)");

  const result = {
    cluster: net.cluster,
    programId: oc.programId.toBase58(),
    config: r.config.toBase58(),
    pool: r.pool.toBase58(),
    baseMint: r.baseMint.toBase58(),
    treasury: r.treasury.toBase58(),
    treasuryQuote: r.treasuryQuote.toBase58(),
    fundedSol: sol(funded),
    migrated,
    txs: Object.fromEntries(Object.entries(st.sigs).map(([k, v]) => [k, net.explorer(v)])),
  };
  fs.mkdirSync(".owncurve", { recursive: true });
  fs.writeFileSync(`.owncurve/f1-result-${net.cluster}.json`, JSON.stringify(result, null, 2));
  console.log(`\n  PUERTA F1 SUPERADA: la tesorería PDA cobró el migration fee por CPI.\n`);
  for (const [k, v] of Object.entries(result.txs)) console.log(`  ${k.padEnd(8)} ${v}`);
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error(`\n  ✘ ${e.message ?? e}`);
    if (e instanceof TxError && e.logs) {
      console.error("  Logs del programa (últimas 25 líneas):");
      for (const l of e.logs.slice(-25)) console.error("    " + l);
    }
    process.exit(1);
  });
