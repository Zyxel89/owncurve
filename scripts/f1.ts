// F1.2–F1.5 · Validación técnica de OwnCurve sobre Meteora DBC.
//
//  1. init_raise + DBC create_config en UNA transacción (fee_claimer y leftover = tesorería PDA)
//  2. DBC create_pool + bind_pool en UNA transacción (el launch nace validado)
//  3. Compras hasta completar la curva
//  4. harvest: CPI withdraw_migration_fee firmada por la PDA → la tesorería recibe el 80%
//  5. (opcional, --migrate) migración a DAMM v2
//
// Reanudable: guarda claves y progreso en .owncurve/f1-<cluster>.json, así un fallo de red
// no obliga a empezar de cero ni a gastar SOL de nuevo.
//
// Uso:  npx tsx scripts/f1.ts            (devnet)
//       CLUSTER=local npx tsx scripts/f1.ts   (LiteSVM con los .so reales)
import { AnchorProvider, BN, Program, Wallet } from "@anchor-lang/core";
import {
  ActivationType,
  BaseFeeMode,
  CollectFeeMode,
  DAMM_V2_MIGRATION_FEE_ADDRESS,
  DammV2DynamicFeeMode,
  DynamicBondingCurveClient,
  MigratedCollectFeeMode,
  MigrationFeeOption,
  MigrationOption,
  SwapMode,
  TokenAuthorityOption,
  TokenDecimal,
  TokenType,
  buildCurve,
  deriveDbcEventAuthority,
  deriveDbcPoolAddress,
  deriveDbcPoolAuthority,
  getCurrentPoint,
} from "@meteora-ag/dynamic-bonding-curve-sdk";
import {
  NATIVE_MINT,
  TOKEN_PROGRAM_ID,
  createAssociatedTokenAccountIdempotentInstruction,
  getAssociatedTokenAddressSync,
} from "@solana/spl-token";
import { Keypair, LAMPORTS_PER_SOL, PublicKey, SystemProgram, TransactionInstruction } from "@solana/web3.js";
import fs from "fs";
import { Net, TxError, makeNet } from "./lib/net";
import { createLocalDammV2Config } from "./lib/local-damm";

// ---------------------------------------------------------------- parámetros
const THRESHOLD_SOL = Number(process.env.THRESHOLD_SOL ?? "0.5"); // SOL para graduar
const TREASURY_PCT = 80; // % de lo recaudado que va a la tesorería
const TRANCHES_BPS = [3000, 3000, 4000]; // 3 hitos: 30% / 30% / 40%
const CHALLENGE_SECS = 60; // ventana de rechazo (corta para la demo)
const QUORUM_BPS = 1000; // 10% del suministro bloqueado en "rechazo" bloquea el tramo
const DBC = new PublicKey("dbcij3LWUppWqq96dh6gJWwBifmcGfLSB5D4DuSMaqN");

const DO_MIGRATE = process.argv.includes("--migrate");

type State = {
  programId: string;
  config: number[];
  baseMint: number[];
  sigs: Record<string, string>;
};

function log(step: string, msg: string) {
  console.log(`  ✔ ${step.padEnd(12)} ${msg}`);
}
const sol = (lamports: number | bigint | BN) => (Number(lamports.toString()) / LAMPORTS_PER_SOL).toFixed(4);
const kp = (s: number[]) => Keypair.fromSecretKey(Uint8Array.from(s));
const ps = (p: any) => p.poolState ?? p; // SDK ≥1.5.8 anida el estado en poolState
const stateName = (s: any) => Object.keys(s)[0];

export function curveConfig() {
  return buildCurve({
    token: {
      tokenType: TokenType.Token2022,
      tokenBaseDecimal: TokenDecimal.SIX,
      tokenQuoteDecimal: TokenDecimal.NINE,
      tokenAuthorityOption: TokenAuthorityOption.Immutable,
      totalTokenSupply: 1_000_000_000,
      leftover: 0,
    },
    fee: {
      baseFeeParams: {
        baseFeeMode: BaseFeeMode.FeeSchedulerLinear,
        feeSchedulerParam: { startingFeeBps: 100, endingFeeBps: 100, numberOfPeriod: 0, totalDuration: 0 },
      },
      dynamicFeeEnabled: false,
      collectFeeMode: CollectFeeMode.QuoteToken,
      creatorTradingFeePercentage: 0,
      poolCreationFee: 0,
      enableFirstSwapWithMinFee: false,
    },
    migration: {
      migrationOption: MigrationOption.MET_DAMM_V2,
      migrationFeeOption: MigrationFeeOption.Customizable,
      migrationFee: { feePercentage: TREASURY_PCT, creatorFeePercentage: 0 },
      migratedPoolFee: {
        collectFeeMode: MigratedCollectFeeMode.QuoteToken,
        dynamicFee: DammV2DynamicFeeMode.Disabled,
        poolFeeBps: 100,
      },
    },
    // El LP graduado queda 100% bloqueado a nombre del partner = la tesorería.
    liquidityDistribution: {
      partnerPermanentLockedLiquidityPercentage: 100,
      partnerLiquidityPercentage: 0,
      creatorPermanentLockedLiquidityPercentage: 0,
      creatorLiquidityPercentage: 0,
    },
    lockedVesting: {
      totalLockedVestingAmount: 0,
      numberOfVestingPeriod: 0,
      cliffUnlockAmount: 0,
      totalVestingDuration: 0,
      cliffDurationFromMigrationTime: 0,
    },
    activationType: ActivationType.Timestamp,
    // Con el 80% a tesorería, solo el 20% de lo recaudado entra al pool: el % de suministro
    // que migra debe ser < 0,2·(1−s) ⇒ s < 16,7%. Usamos 10% con margen.
    percentageSupplyOnMigration: 10,
    migrationQuoteThreshold: THRESHOLD_SOL,
  });
}

async function main() {
  const net = await makeNet();
  const idl = JSON.parse(fs.readFileSync("target/idl/owncurve.json", "utf8"));
  const programId = new PublicKey(idl.address);
  const provider = new AnchorProvider(net.conn, new Wallet(net.payer), { commitment: "confirmed" });
  const program = new Program(idl, provider) as Program<any>;
  const dbc = new DynamicBondingCurveClient(net.conn, "confirmed");
  const payer = net.payer.publicKey;

  console.log(`\n  Red        : ${net.cluster}`);
  console.log(`  Programa   : ${programId.toBase58()}`);
  console.log(`  Wallet     : ${payer.toBase58()} (${sol(await net.conn.getBalance(payer))} SOL)`);

  const prog = await net.conn.getAccountInfo(programId);
  if (!prog?.executable) throw new Error(`El programa ${programId.toBase58()} no está desplegado en ${net.cluster}`);

  // ------------------------------------------------------------ estado reanudable
  const stateFile = `.owncurve/f1-${net.cluster}.json`;
  let st: State | null = null;
  if (net.cluster === "devnet" && fs.existsSync(stateFile)) {
    st = JSON.parse(fs.readFileSync(stateFile, "utf8"));
    if (st!.programId !== programId.toBase58()) st = null; // otro programa → empezar de cero
  }
  if (!st) {
    st = {
      programId: programId.toBase58(),
      config: Array.from(Keypair.generate().secretKey),
      baseMint: Array.from(Keypair.generate().secretKey),
      sigs: {},
    };
  }
  const save = () => {
    if (net.cluster !== "devnet") return;
    fs.mkdirSync(".owncurve", { recursive: true });
    fs.writeFileSync(stateFile, JSON.stringify(st, null, 2));
  };
  save();

  const configKp = kp(st.config);
  const baseMintKp = kp(st.baseMint);
  const config = configKp.publicKey;
  const [raisePda] = PublicKey.findProgramAddressSync([Buffer.from("raise"), config.toBuffer()], programId);
  const [treasury] = PublicKey.findProgramAddressSync([Buffer.from("treasury"), config.toBuffer()], programId);
  const pool = deriveDbcPoolAddress(NATIVE_MINT, baseMintKp.publicKey, config);
  const treasuryQuote = getAssociatedTokenAddressSync(NATIVE_MINT, treasury, true);
  const fetchRaise = () => (program.account as any).raise.fetchNullable(raisePda);

  console.log(`  Config DBC : ${config.toBase58()}`);
  console.log(`  Tesorería  : ${treasury.toBase58()}\n`);

  // ------------------------------------------------ F1.2  raise + config DBC (atómico)
  if (!(await fetchRaise())) {
    const initRaise = await program.methods
      .initRaise({
        minTreasuryPct: TREASURY_PCT,
        trancheBps: TRANCHES_BPS,
        challengeWindow: new BN(CHALLENGE_SECS),
        rejectQuorumBps: QUORUM_BPS,
      })
      .accountsStrict({
        team: payer,
        dbcConfig: config,
        raise: raisePda,
        treasury,
        systemProgram: SystemProgram.programId,
      })
      .instruction();
    const createConfig = await dbc.partner.createConfig({
      config,
      feeClaimer: treasury,
      leftoverReceiver: treasury,
      payer,
      quoteMint: NATIVE_MINT,
      ...curveConfig(),
    });
    st.sigs.raise = await net.send("init_raise + create_config", [initRaise, ...createConfig.instructions], [configKp]);
    save();
  }
  const cfg = await dbc.state.getPoolConfig(config);
  if (!cfg) throw new Error("La config DBC no existe tras crearla");
  if (!new PublicKey(cfg.feeClaimer).equals(treasury)) throw new Error("fee_claimer no es la tesorería");
  log("F1.2 config", `fee_claimer = tesorería · migration fee ${cfg.migrationFeePercentage}% · umbral ${sol(cfg.migrationQuoteThreshold)} SOL`);

  // ------------------------------------------------ F1.3a pool + bind_pool (atómico)
  let raise = await fetchRaise();
  if (stateName(raise.state) === "pending") {
    const ixs: TransactionInstruction[] = [];
    if (!(await net.conn.getAccountInfo(pool))) {
      const createPool = await dbc.creator.createPool({
        baseMint: baseMintKp.publicKey,
        config,
        name: "OwnCurve Demo",
        symbol: "OWND",
        uri: "https://raw.githubusercontent.com/solana-developers/opos-asset/main/assets/DeveloperPortal/metadata.json",
        payer,
        poolCreator: payer,
      });
      ixs.push(...createPool.instructions);
    }
    ixs.push(
      await program.methods
        .bindPool()
        .accountsStrict({ raise: raisePda, treasury, dbcConfig: config, dbcPool: pool })
        .instruction(),
    );
    st.sigs.pool = await net.send("create_pool + bind_pool", ixs, ixs.length > 1 ? [baseMintKp] : []);
    save();
    raise = await fetchRaise();
  }
  log("F1.3 pool", `${pool.toBase58()} · raise en estado "${stateName(raise.state)}"`);

  // ------------------------------------------------ F1.3b comprar hasta completar la curva
  const threshold = new BN(cfg.migrationQuoteThreshold.toString());
  for (let i = 0; i < 8; i++) {
    const p = await dbc.state.getPool(pool);
    const reserve = new BN(ps(p).quoteReserve.toString());
    if (reserve.gte(threshold)) break;
    const remaining = threshold.sub(reserve);
    const amountIn = remaining.muln(103).divn(100).addn(10_000); // +3% por la comisión
    const currentPoint = await getCurrentPoint(net.conn, cfg.activationType);
    const quote = dbc.pool.swapQuote2({
      virtualPool: p as any,
      config: cfg,
      swapBaseForQuote: false,
      hasReferral: false,
      eligibleForFirstSwapWithMinFee: false,
      currentPoint,
      slippageBps: 500,
      swapMode: SwapMode.PartialFill,
      amountIn,
    });
    const swap = await dbc.pool.swap2({
      owner: payer,
      pool,
      swapBaseForQuote: false,
      referralTokenAccount: null,
      payer,
      swapMode: SwapMode.PartialFill,
      amountIn,
      minimumAmountOut: quote.minimumAmountOut ?? new BN(0),
    });
    st.sigs[`buy${i}`] = await net.send(`compra ${i + 1}`, swap.instructions, []);
    save();
  }
  const pAfter = ps(await dbc.state.getPool(pool));
  if (new BN(pAfter.quoteReserve.toString()).lt(threshold)) throw new Error("La curva no se completó");
  log("F1.3 curva", `completa · reserva ${sol(pAfter.quoteReserve)} SOL ≥ umbral ${sol(threshold)} SOL`);

  // ------------------------------------------------ F1.5 harvest (CPI firmada por la PDA)
  raise = await fetchRaise();
  if (stateName(raise.state) === "bonding") {
    const harvest = await program.methods
      .harvest()
      .accountsStrict({
        raise: raisePda,
        treasury,
        treasuryQuote,
        quoteMint: NATIVE_MINT,
        dbcPoolAuthority: deriveDbcPoolAuthority(),
        dbcConfig: config,
        dbcPool: pool,
        dbcQuoteVault: pAfter.quoteVault,
        dbcEventAuthority: deriveDbcEventAuthority(),
        dbcProgram: DBC,
        quoteTokenProgram: TOKEN_PROGRAM_ID,
      })
      .instruction();
    st.sigs.harvest = await net.send(
      "harvest",
      [createAssociatedTokenAccountIdempotentInstruction(payer, treasuryQuote, treasury, NATIVE_MINT), harvest],
      [],
    );
    save();
    raise = await fetchRaise();
  }
  const bal = await net.conn.getTokenAccountBalance(treasuryQuote);
  const expected = threshold.muln(TREASURY_PCT).divn(100);
  const funded = new BN(raise.fundedAmount.toString());
  const okHarvest = stateName(raise.state) === "funded" && funded.eq(expected) && bal.value.amount === funded.toString();
  if (!okHarvest) {
    throw new Error(
      `harvest no cuadra: estado=${stateName(raise.state)} funded=${funded} esperado=${expected} saldo=${bal.value.amount}`,
    );
  }
  log("F1.5 harvest", `tesorería = ${sol(funded)} SOL (${TREASURY_PCT}% de ${sol(threshold)}) · estado "funded"`);

  // ------------------------------------------------ F1.4 migración a DAMM v2 (opcional)
  let migrated = Boolean(ps(await dbc.state.getPool(pool)).isMigrated);
  if (DO_MIGRATE && !migrated) {
    try {
      // devnet/mainnet: config dinámica de Meteora para el modo Customizable.
      // local: la creamos nosotros con los mismos requisitos.
      const dammConfig =
        net.cluster === "local"
          ? await createLocalDammV2Config(net)
          : DAMM_V2_MIGRATION_FEE_ADDRESS[MigrationFeeOption.Customizable];
      const m = await dbc.migration.migrateToDammV2({
        payer,
        pool,
        dammConfig,
      });
      st.sigs.migrate = await net.send("migrate_damm_v2", m.transaction.instructions, [
        m.firstPositionNftKeypair,
        m.secondPositionNftKeypair,
      ]);
      save();
      migrated = true;
    } catch (e: any) {
      console.log(`  ! F1.4 migración: falló (${String(e.message).slice(0, 120)})`);
      if (e instanceof TxError && e.logs) for (const l of e.logs.slice(-15)) console.log("      " + l);
      console.log(`    No bloquea F1. Alternativa: https://migrator.meteora.ag  con el pool ${pool.toBase58()}`);
    }
  }
  if (migrated) log("F1.4 migrar", "pool graduado a DAMM v2");
  else if (!DO_MIGRATE) console.log("  · F1.4 migrar  pendiente (ejecuta con --migrate)");

  // ------------------------------------------------ resumen
  const result = {
    cluster: net.cluster,
    programId: programId.toBase58(),
    config: config.toBase58(),
    pool: pool.toBase58(),
    baseMint: baseMintKp.publicKey.toBase58(),
    treasury: treasury.toBase58(),
    treasuryQuote: treasuryQuote.toBase58(),
    fundedSol: sol(funded),
    migrated,
    txs: Object.fromEntries(Object.entries(st.sigs).map(([k, v]) => [k, net.explorer(v)])),
  };
  fs.mkdirSync(".owncurve", { recursive: true });
  fs.writeFileSync(`.owncurve/f1-result-${net.cluster}.json`, JSON.stringify(result, null, 2));
  console.log(`\n  PUERTA F1 SUPERADA: la tesorería PDA cobró el migration fee por CPI.\n`);
  for (const [k, v] of Object.entries(result.txs)) console.log(`  ${k.padEnd(8)} ${v}`);
}

main().then(() => process.exit(0)).catch((e) => {
  console.error(`\n  ✘ ${e.message ?? e}`);
  if (e instanceof TxError && e.logs) {
    console.error("  Logs del programa (últimas 25 líneas):");
    for (const l of e.logs.slice(-25)) console.error("    " + l);
  }
  process.exit(1);
});
