// Cliente de OwnCurve: todas las operaciones del ciclo de vida de un raise.
// Lo usan el script de devnet (scripts/f1.ts) y los tests (tests/owncurve.test.ts).
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
  createDammV2Program,
  deriveDammV2EventAuthority,
  deriveDammV2PoolAddress,
  deriveDammV2PoolAuthority,
  deriveDammV2TokenVaultAddress,
  deriveDbcEventAuthority,
  deriveDbcPoolAddress,
  deriveDbcPoolAuthority,
  getCurrentPoint,
} from "@meteora-ag/dynamic-bonding-curve-sdk";
import {
  NATIVE_MINT,
  TOKEN_2022_PROGRAM_ID,
  TOKEN_PROGRAM_ID,
  createAssociatedTokenAccountIdempotentInstruction,
  createSyncNativeInstruction,
  createTransferCheckedInstruction,
  getAssociatedTokenAddressSync,
} from "@solana/spl-token";
import { Keypair, PublicKey, SystemProgram, TransactionInstruction } from "@solana/web3.js";
import { createLocalDammV2Config } from "./local-damm";
import type { Net } from "./net";

export const DBC = new PublicKey("dbcij3LWUppWqq96dh6gJWwBifmcGfLSB5D4DuSMaqN");
export const DAMM_V2 = new PublicKey("cpamdpZCGKUy5JxQXB4dcpGPiikHawvSWAd6mEn1sGG");
export const BASE_DECIMALS = 6;

/** Moneda en la que se recauda (quote). SOL por defecto; cualquier SPL o Token-2022 (USDC, xStocks…). */
export type Quote = { mint: PublicKey; program: PublicKey; decimals: number; symbol: string };
export const SOL_QUOTE: Quote = { mint: NATIVE_MINT, program: TOKEN_PROGRAM_ID, decimals: 9, symbol: "SOL" };

export type RaiseParams = {
  /** Lo que la curva recauda antes de graduar, en unidades de la moneda (p. ej. 0.5 SOL, 100 USDC). */
  threshold: number;
  quote?: Quote;
  treasuryPct: number; // % de lo recaudado que va a la tesorería (migration fee)
  tranchesBps: number[];
  challengeSecs: number;
  quorumBps: number;
  floorReserveBps: number; // parte de lo recaudado que nunca se paga: respalda el piso de precio
  /** Protecciones automáticas (cuenta Guard): equipo fantasma y cláusula Bedrock en cadena. */
  guard?: GuardParams | null;
  /** Presupuesto entre hitos: `amount` (en la moneda del raise) cada `periodSecs`, adelanto del siguiente tramo. */
  budget?: { amount: number; periodSecs: number } | null;
  // Solo para tests de seguridad: configs DBC "maliciosas".
  feeClaimer?: PublicKey;
  creatorMigrationFeePct?: number;
  creatorUnlockedLpPct?: number;
};

export type GuardParams = { inactivitySecs: number; buyoutPremiumBps: number; twapWindowSecs: number };
/** Valores de devnet (minutos, para poder enseñarlo); en mainnet serían semanas y +30%. */
export const DEFAULT_GUARD: GuardParams = { inactivitySecs: 300, buyoutPremiumBps: 3000, twapWindowSecs: 120 };

export const DEFAULT_PARAMS: RaiseParams = {
  threshold: 0.5,
  treasuryPct: 80,
  tranchesBps: [3000, 3000, 4000],
  challengeSecs: 60,
  quorumBps: 1000,
  floorReserveBps: 2000,
  guard: DEFAULT_GUARD,
};

export type Evidence = { uri: string; hash: number[] };

/** SHA-256 en Node y en el navegador. */
export async function sha256(text: string): Promise<number[]> {
  const data = new TextEncoder().encode(text);
  const buf = await (globalThis.crypto as Crypto).subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(buf));
}

export async function evidence(uri: string, committed?: string): Promise<Evidence> {
  return { uri, hash: await sha256(committed?.trim() || uri) };
}

export const ps = (p: any) => p.poolState ?? p; // SDK ≥1.5.8 anida el estado del pool
export const stateName = (s: any) => Object.keys(s)[0];

export function curveConfig(p: RaiseParams) {
  // Con t% a la tesorería, solo (100−t)% de lo recaudado entra al pool: el % de suministro
  // que migra debe ser s < (1−t)(1−s) para que el precio de graduación quede por encima
  // de la curva. Para t=80 ⇒ s < 16,7%. Usamos la mitad del límite.
  const r = 1 - p.treasuryPct / 100;
  const supplyPct = Math.max(1, Math.floor(((r / (1 + r)) * 100) / 2));
  return buildCurve({
    token: {
      tokenType: TokenType.Token2022,
      tokenBaseDecimal: TokenDecimal.SIX,
      tokenQuoteDecimal: (p.quote?.decimals ?? 9) as TokenDecimal,
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
      migrationFee: { feePercentage: p.treasuryPct, creatorFeePercentage: p.creatorMigrationFeePct ?? 0 },
      migratedPoolFee: {
        collectFeeMode: MigratedCollectFeeMode.QuoteToken,
        dynamicFee: DammV2DynamicFeeMode.Disabled,
        poolFeeBps: 100,
      },
    },
    // El LP graduado queda 100% bloqueado a nombre del partner = la tesorería.
    liquidityDistribution: {
      partnerPermanentLockedLiquidityPercentage: 100 - (p.creatorUnlockedLpPct ?? 0),
      partnerLiquidityPercentage: 0,
      creatorPermanentLockedLiquidityPercentage: 0,
      creatorLiquidityPercentage: p.creatorUnlockedLpPct ?? 0,
    },
    lockedVesting: {
      totalLockedVestingAmount: 0,
      numberOfVestingPeriod: 0,
      cliffUnlockAmount: 0,
      totalVestingDuration: 0,
      cliffDurationFromMigrationTime: 0,
    },
    activationType: ActivationType.Timestamp,
    percentageSupplyOnMigration: supplyPct,
    migrationQuoteThreshold: p.threshold,
  });
}

export class Raise {
  constructor(
    readonly oc: OwnCurve,
    readonly config: PublicKey,
    readonly baseMint: PublicKey,
    readonly quoteMint: PublicKey = NATIVE_MINT,
    readonly quoteProgram: PublicKey = TOKEN_PROGRAM_ID,
  ) {}
  get isSol() {
    return this.quoteMint.equals(NATIVE_MINT);
  }
  /** Lee de la cadena el mint base y la moneda del raise (o de su config DBC si aún no tiene pool). */
  static async load(oc: OwnCurve, config: PublicKey): Promise<Raise> {
    const pda = PublicKey.findProgramAddressSync([Buffer.from("raise"), config.toBuffer()], oc.programId)[0];
    const raise = await (oc.program.account as any).raise.fetch(pda);
    let quoteMint = new PublicKey(raise.quoteMint);
    if (quoteMint.equals(PublicKey.default)) {
      const cfg = await oc.dbc.state.getPoolConfig(config).catch(() => null);
      quoteMint = cfg ? new PublicKey(cfg.quoteMint) : NATIVE_MINT;
    }
    const q = await oc.quoteInfo(quoteMint);
    return new Raise(oc, config, new PublicKey(raise.baseMint), q.mint, q.program);
  }
  get pid() {
    return this.oc.programId;
  }
  get raise() {
    return PublicKey.findProgramAddressSync([Buffer.from("raise"), this.config.toBuffer()], this.pid)[0];
  }
  get treasury() {
    return PublicKey.findProgramAddressSync([Buffer.from("treasury"), this.config.toBuffer()], this.pid)[0];
  }
  get guard() {
    return PublicKey.findProgramAddressSync([Buffer.from("guard"), this.raise.toBuffer()], this.pid)[0];
  }
  get budget() {
    return PublicKey.findProgramAddressSync([Buffer.from("budget"), this.raise.toBuffer()], this.pid)[0];
  }
  get escrow() {
    return PublicKey.findProgramAddressSync([Buffer.from("escrow"), this.raise.toBuffer()], this.pid)[0];
  }
  get pool() {
    return deriveDbcPoolAddress(this.quoteMint, this.baseMint, this.config);
  }
  get treasuryQuote() {
    return getAssociatedTokenAddressSync(this.quoteMint, this.treasury, true, this.quoteProgram);
  }
  get treasuryBase() {
    return getAssociatedTokenAddressSync(this.baseMint, this.treasury, true, TOKEN_2022_PROGRAM_ID);
  }
  get escrowBase() {
    return getAssociatedTokenAddressSync(this.baseMint, this.escrow, true, TOKEN_2022_PROGRAM_ID);
  }
  baseAta(owner: PublicKey) {
    return getAssociatedTokenAddressSync(this.baseMint, owner, true, TOKEN_2022_PROGRAM_ID);
  }
  quoteAta(owner: PublicKey) {
    return getAssociatedTokenAddressSync(this.quoteMint, owner, true, this.quoteProgram);
  }
  voteRecord(voter: PublicKey, nonce: number) {
    return PublicKey.findProgramAddressSync(
      [Buffer.from("vote"), this.raise.toBuffer(), voter.toBuffer(), new BN(nonce).toArrayLike(Buffer, "le", 4)],
      this.pid,
    )[0];
  }
  async fetch(): Promise<any> {
    return (this.oc.program.account as any).raise.fetch(this.raise);
  }
  async fetchNullable(): Promise<any> {
    return (this.oc.program.account as any).raise.fetchNullable(this.raise);
  }
  async state(): Promise<string> {
    return stateName((await this.fetch()).state);
  }
}

export class OwnCurve {
  readonly program: Program<any>;
  readonly dbc: DynamicBondingCurveClient;
  readonly programId: PublicKey;

  constructor(readonly net: Net, idl: any) {
    this.programId = new PublicKey(idl.address);
    // Solo construimos instrucciones (nunca .rpc()), así que el "wallet" del provider
    // no firma nada: basta con la clave pública. Funciona igual en Node y en el navegador.
    const wallet = {
      publicKey: net.payer.publicKey,
      signTransaction: async (t: any) => t,
      signAllTransactions: async (t: any) => t,
    } as unknown as Wallet;
    const provider = new AnchorProvider(net.conn, wallet, { commitment: "confirmed" });
    this.program = new Program(idl, provider) as Program<any>;
    this.dbc = new DynamicBondingCurveClient(net.conn, "confirmed");
  }
  get payer() {
    return this.net.payer.publicKey;
  }
  get m() {
    return this.program.methods as any;
  }

  private quoteCache = new Map<string, Quote>();
  /** Programa de token, decimales y símbolo de una moneda. */
  async quoteInfo(mint: PublicKey, symbol?: string): Promise<Quote> {
    if (mint.equals(NATIVE_MINT)) return SOL_QUOTE;
    const hit = this.quoteCache.get(mint.toBase58());
    if (hit) return hit;
    const info = await this.net.conn.getAccountInfo(mint);
    if (!info) throw new Error(`La moneda ${mint.toBase58()} no existe en esta red`);
    const program = new PublicKey(info.owner);
    const decimals = info.data[44];
    let sym = symbol;
    if (!sym && program.equals(TOKEN_2022_PROGRAM_ID)) {
      try {
        const { getTokenMetadata } = await import("@solana/spl-token");
        sym = (await getTokenMetadata(this.net.conn, mint, "confirmed", TOKEN_2022_PROGRAM_ID))?.symbol;
      } catch {
        /* sin metadata */
      }
    }
    const q = { mint, program, decimals, symbol: sym || mint.toBase58().slice(0, 4) };
    this.quoteCache.set(mint.toBase58(), q);
    return q;
  }

  // ---------------------------------------------------------------- creación
  /** init_raise + create_config de DBC en UNA transacción. */
  async createRaise(params: RaiseParams, configKp = Keypair.generate(), team = this.net.payer) {
    const r = new Raise(this, configKp.publicKey, PublicKey.default);
    const initRaise = await this.m
      .initRaise({
        minTreasuryPct: params.treasuryPct,
        trancheBps: params.tranchesBps,
        challengeWindow: new BN(params.challengeSecs),
        rejectQuorumBps: params.quorumBps,
        floorReserveBps: params.floorReserveBps,
      })
      .accountsStrict({
        team: team.publicKey,
        dbcConfig: configKp.publicKey,
        raise: r.raise,
        treasury: r.treasury,
        systemProgram: SystemProgram.programId,
      })
      .instruction();
    const createConfig = await this.dbc.partner.createConfig({
      config: configKp.publicKey,
      feeClaimer: params.feeClaimer ?? r.treasury,
      leftoverReceiver: r.treasury,
      payer: this.payer,
      quoteMint: params.quote?.mint ?? NATIVE_MINT,
      ...curveConfig(params),
    });
    const guardIxs = params.guard
      ? [
          await this.m
            .initGuard({
              inactivitySecs: new BN(params.guard.inactivitySecs),
              buyoutPremiumBps: params.guard.buyoutPremiumBps,
              twapWindowSecs: new BN(params.guard.twapWindowSecs),
            })
            .accountsStrict({ team: team.publicKey, raise: r.raise, guard: r.guard, systemProgram: SystemProgram.programId })
            .instruction(),
        ]
      : [];
    if (params.budget && params.budget.amount > 0) {
      const dec = params.quote?.decimals ?? 9;
      guardIxs.push(
        await this.m
          .initBudget({
            monthlyAmount: new BN(Math.round(params.budget.amount * 10 ** dec).toString()),
            periodSecs: new BN(params.budget.periodSecs),
          })
          .accountsStrict({ team: team.publicKey, raise: r.raise, budget: r.budget, systemProgram: SystemProgram.programId })
          .instruction(),
      );
    }
    const sig = await this.net.send("init_raise + create_config", [initRaise, ...createConfig.instructions, ...guardIxs], [
      configKp,
      team,
    ]);
    return { sig, configKp };
  }

  /** create_pool de DBC + bind_pool en UNA transacción: el launch nace validado. */
  async launchPool(
    config: PublicKey,
    baseMintKp = Keypair.generate(),
    team = this.net.payer,
    withPool = true,
    meta: { name: string; symbol: string; uri: string } = {
      name: "OwnCurve Demo",
      symbol: "OWND",
      uri: "https://raw.githubusercontent.com/solana-developers/opos-asset/main/assets/DeveloperPortal/metadata.json",
    },
  ) {
    const cfg = await this.dbc.state.getPoolConfig(config);
    const q = await this.quoteInfo(new PublicKey(cfg!.quoteMint));
    const r = new Raise(this, config, baseMintKp.publicKey, q.mint, q.program);
    const ixs: TransactionInstruction[] = [];
    if (withPool && !(await this.net.conn.getAccountInfo(r.pool))) {
      const createPool = await this.dbc.creator.createPool({
        baseMint: baseMintKp.publicKey,
        config,
        ...meta,
        payer: this.payer,
        poolCreator: team.publicKey,
      });
      ixs.push(...createPool.instructions);
    }
    ixs.push(
      await this.m
        .bindPool()
        .accountsStrict({ raise: r.raise, treasury: r.treasury, dbcConfig: config, dbcPool: r.pool })
        .instruction(),
    );
    const sig = await this.net.send("create_pool + bind_pool", ixs, ixs.length > 1 ? [baseMintKp, team] : []);
    return { sig, raise: r };
  }

  // ---------------------------------------------------------------- curva
  /** Compra en la curva con `lamportsIn` de SOL. PartialFill nunca pasa del umbral;
   *  ExactIn puede pasarse y deja un excedente ("surplus") en el pool. */
  async buy(r: Raise, lamportsIn: BN, buyer = this.net.payer, mode: SwapMode.PartialFill | SwapMode.ExactIn = SwapMode.PartialFill) {
    const cfg = await this.dbc.state.getPoolConfig(r.config);
    const pool = await this.dbc.state.getPool(r.pool);
    const quote = this.dbc.pool.swapQuote2({
      virtualPool: pool as any,
      config: cfg!,
      swapBaseForQuote: false,
      hasReferral: false,
      eligibleForFirstSwapWithMinFee: false,
      currentPoint: await getCurrentPoint(this.net.conn, cfg!.activationType),
      slippageBps: 500,
      swapMode: mode,
      amountIn: lamportsIn,
    });
    const swap = await this.dbc.pool.swap2({
      owner: buyer.publicKey,
      pool: r.pool,
      swapBaseForQuote: false,
      referralTokenAccount: null,
      payer: buyer.publicKey,
      swapMode: mode,
      amountIn: lamportsIn,
      minimumAmountOut: quote.minimumAmountOut ?? new BN(0),
    });
    return this.net.send("compra en la curva", swap.instructions, [buyer]);
  }

  async curve(r: Raise) {
    const cfg = await this.dbc.state.getPoolConfig(r.config);
    const pool = ps(await this.dbc.state.getPool(r.pool));
    const threshold = new BN(cfg!.migrationQuoteThreshold.toString());
    const reserve = new BN(pool.quoteReserve.toString());
    return { cfg: cfg!, pool, threshold, reserve, complete: reserve.gte(threshold) };
  }

  async buyToComplete(r: Raise, buyer = this.net.payer) {
    const sigs: string[] = [];
    for (let i = 0; i < 8; i++) {
      const c = await this.curve(r);
      if (c.complete) return sigs;
      const remaining = c.threshold.sub(c.reserve);
      sigs.push(await this.buy(r, remaining.muln(103).divn(100).addn(10_000), buyer));
    }
    throw new Error("La curva no se completó tras 8 compras");
  }

  // ---------------------------------------------------------------- tesorería
  private dbcAccounts(r: Raise, pool: any) {
    return {
      dbcPoolAuthority: deriveDbcPoolAuthority(),
      dbcConfig: r.config,
      dbcPool: r.pool,
      dbcQuoteVault: pool.quoteVault,
      dbcEventAuthority: deriveDbcEventAuthority(),
      dbcProgram: DBC,
    };
  }

  private ensureTreasuryAtas(r: Raise) {
    return [
      createAssociatedTokenAccountIdempotentInstruction(this.payer, r.treasuryQuote, r.treasury, r.quoteMint, r.quoteProgram),
      createAssociatedTokenAccountIdempotentInstruction(
        this.payer,
        r.treasuryBase,
        r.treasury,
        r.baseMint,
        TOKEN_2022_PROGRAM_ID,
      ),
    ];
  }

  async harvest(r: Raise) {
    const { pool } = await this.curve(r);
    const ix = await this.m
      .harvest()
      .accountsStrict({
        raise: r.raise,
        treasury: r.treasury,
        treasuryQuote: r.treasuryQuote,
        quoteMint: r.quoteMint,
        ...this.dbcAccounts(r, pool),
        quoteTokenProgram: r.quoteProgram,
      })
      .instruction();
    // Si el raise tiene guard, su reloj de inactividad arranca en la misma transacción.
    const arm = (await this.net.conn.getAccountInfo(r.guard))
      ? [await this.m.armGuard().accountsStrict({ raise: r.raise, guard: r.guard }).instruction()]
      : [];
    return this.net.send("harvest", [...this.ensureTreasuryAtas(r), ix, ...arm], []);
  }

  // ---------------------------------------------------------------- guard
  /** Estado del guard con el TWAP y el coste de una oferta pública calculados como el programa. */
  async guardState(r: Raise) {
    const g: any = await (this.program.account as any).guard.fetchNullable(r.guard);
    if (!g) return null;
    const now = Math.floor(Date.now() / 1000) + (await this.clockSkew());
    const window = Number(g.twapWindowSecs);
    const obs = (g.observations as any[])
      .slice(0, g.obsCount)
      .map((o) => ({ ts: Number(o.ts), priceQ64: BigInt(o.priceQ64.toString()) }));
    const inWindow = obs.filter((o) => o.ts >= now - window);
    const oldest = inWindow.length ? Math.min(...inWindow.map((o) => o.ts)) : now;
    const twapReady = inWindow.length >= 3 && now - oldest >= window / 2;
    const twapQ64 = inWindow.length ? inWindow.reduce((a, o) => a + o.priceQ64, 0n) / BigInt(inWindow.length) : 0n;
    const buyoutQ64 = (twapQ64 * BigInt(10_000 + g.buyoutPremiumBps)) / 10_000n;
    const raise = await r.fetch();
    const circulating = BigInt((await this.mintSupply(r.baseMint)).sub(await this.tokenBalance(r.treasuryBase)).toString());
    const treasury = BigInt((await this.tokenBalance(r.treasuryQuote)).toString());
    const required = (buyoutQ64 * circulating) >> 64n;
    const deposit = required > treasury ? required - treasury : 0n;
    const lastObs = obs.length ? Math.max(...obs.map((o) => o.ts)) : null;
    const silentSince = Math.max(Number(g.armedAt), Number(raise.proposalEndsAt));
    return {
      inactivitySecs: Number(g.inactivitySecs),
      armedAt: Number(g.armedAt),
      abandonableAt: Number(g.armedAt) > 0 ? silentSince + Number(g.inactivitySecs) : null,
      buyoutPremiumBps: g.buyoutPremiumBps as number,
      twapWindowSecs: window,
      observeIntervalSecs: Number(g.observeIntervalSecs),
      nextObserveAt: lastObs === null ? 0 : lastObs + Number(g.observeIntervalSecs),
      observations: obs,
      observationsInWindow: inWindow.length,
      twapReady,
      /** precios en unidades atómicas de moneda por unidad atómica de token */
      twap: Number(twapQ64) / 2 ** 64,
      buyoutPrice: Number(buyoutQ64) / 2 ** 64,
      buyoutDeposit: new BN(deposit.toString()),
      acquirer: new PublicKey(g.acquirer),
      acquired: !new PublicKey(g.acquirer).equals(PublicKey.default),
      abandoned: Boolean(g.abandoned),
      now,
    };
  }

  private async clockSkew() {
    try {
      const t = await this.net.conn.getBlockTime(await this.net.conn.getSlot());
      return t ? t - Math.floor(Date.now() / 1000) : 0;
    } catch {
      return 0;
    }
  }

  /** Presupuesto: lo disponible ahora, como lo calcula `draw_budget`. */
  async budgetState(r: Raise) {
    const b: any = await (this.program.account as any).budget.fetchNullable(r.budget);
    if (!b) return null;
    const raise = await r.fetch();
    const now = Math.floor(Date.now() / 1000) + (await this.clockSkew());
    const start = Number(b.startAt);
    const period = Number(b.periodSecs);
    const periods = start === 0 ? 1 : Math.floor((now - start) / period) + 1;
    const monthly = new BN(b.monthlyAmount.toString());
    const drawn = new BN(b.drawnTotal.toString());
    const advanced = new BN(b.advancedUnsettled.toString());
    const count = Number(raise.milestoneCount);
    const next = (raise.milestones as any[]).slice(0, count).findIndex((m) => stateName(m.status) !== "released");
    const funded = new BN(raise.fundedAmount.toString());
    const payable = funded.sub(funded.muln(raise.floorReserveBps).divn(10_000));
    const nextAmount =
      next < 0 ? new BN(0) : next === count - 1 ? payable.sub(new BN(raise.releasedAmount.toString())) : payable.muln(raise.milestones[next].trancheBps).divn(10_000);
    let available = monthly.muln(periods).sub(drawn);
    const room = nextAmount.sub(advanced);
    if (room.lt(available)) available = room;
    if (available.isNeg()) available = new BN(0);
    return {
      monthly,
      periodSecs: period,
      drawnTotal: drawn,
      advancedUnsettled: advanced,
      nextTranche: next,
      nextTrancheAmount: nextAmount,
      available,
      nextPeriodAt: start === 0 ? now : start + periods * period,
      now,
    };
  }

  async drawBudget(r: Raise, team = this.net.payer) {
    const raise = await r.fetch();
    const teamQuote = r.quoteAta(raise.team);
    const ix = await this.m
      .drawBudget()
      .accountsStrict({
        team: team.publicKey,
        raise: r.raise,
        budget: r.budget,
        treasury: r.treasury,
        treasuryQuote: r.treasuryQuote,
        teamQuote,
        quoteMint: r.quoteMint,
        quoteTokenProgram: r.quoteProgram,
      })
      .instruction();
    return this.net.send(
      "draw_budget",
      [createAssociatedTokenAccountIdempotentInstruction(this.payer, teamQuote, raise.team, r.quoteMint, r.quoteProgram), ix],
      [team],
    );
  }

  async armGuard(r: Raise) {
    const ix = await this.m.armGuard().accountsStrict({ raise: r.raise, guard: r.guard }).instruction();
    return this.net.send("arm_guard", [ix], []);
  }

  async declareAbandoned(r: Raise) {
    const ix = await this.m.declareAbandoned().accountsStrict({ raise: r.raise, guard: r.guard }).instruction();
    return this.net.send("declare_abandoned", [ix], []);
  }

  async observe(r: Raise) {
    const ix = await this.m
      .observe()
      .accountsStrict({ raise: r.raise, guard: r.guard, dammPool: await this.dammPool(r) })
      .instruction();
    return this.net.send("observe", [ix], []);
  }

  /** Oferta pública: `acquirer` aporta lo que falte para pagar TWAP × (1 + prima) por token. */
  async tenderOffer(r: Raise, maxDeposit: BN, acquirer = this.net.payer) {
    const ix = await this.m
      .tenderOffer(maxDeposit)
      .accountsStrict({
        acquirer: acquirer.publicKey,
        raise: r.raise,
        guard: r.guard,
        treasury: r.treasury,
        treasuryQuote: r.treasuryQuote,
        treasuryBase: r.treasuryBase,
        acquirerQuote: r.quoteAta(acquirer.publicKey),
        quoteMint: r.quoteMint,
        baseMint: r.baseMint,
        quoteTokenProgram: r.quoteProgram,
      })
      .instruction();
    const pre = r.isSol
      ? [
          createAssociatedTokenAccountIdempotentInstruction(acquirer.publicKey, r.quoteAta(acquirer.publicKey), acquirer.publicKey, r.quoteMint, r.quoteProgram),
          SystemProgram.transfer({ fromPubkey: acquirer.publicKey, toPubkey: r.quoteAta(acquirer.publicKey), lamports: BigInt(maxDeposit.toString()) }),
          createSyncNativeInstruction(r.quoteAta(acquirer.publicKey)),
        ]
      : [];
    return this.net.send("tender_offer", [...pre, ix], [acquirer]);
  }

  async collectTradingFees(r: Raise) {
    const { pool } = await this.curve(r);
    const ix = await this.m
      .collectTradingFees()
      .accountsStrict({
        raise: r.raise,
        treasury: r.treasury,
        treasuryBase: r.treasuryBase,
        treasuryQuote: r.treasuryQuote,
        baseMint: r.baseMint,
        quoteMint: r.quoteMint,
        ...this.dbcAccounts(r, pool),
        dbcBaseVault: pool.baseVault,
        baseTokenProgram: TOKEN_2022_PROGRAM_ID,
        quoteTokenProgram: r.quoteProgram,
      })
      .instruction();
    return this.net.send("collect_trading_fees", [...this.ensureTreasuryAtas(r), ix], []);
  }

  async collectSurplus(r: Raise) {
    const { pool } = await this.curve(r);
    const ix = await this.m
      .collectSurplus()
      .accountsStrict({
        raise: r.raise,
        treasury: r.treasury,
        treasuryQuote: r.treasuryQuote,
        quoteMint: r.quoteMint,
        ...this.dbcAccounts(r, pool),
        quoteTokenProgram: r.quoteProgram,
      })
      .instruction();
    return this.net.send("collect_surplus", [ix], []);
  }

  // ---------------------------------------------------------------- DAMM v2
  async dammConfig(): Promise<PublicKey> {
    return this.net.cluster === "local"
      ? createLocalDammV2Config(this.net)
      : DAMM_V2_MIGRATION_FEE_ADDRESS[MigrationFeeOption.Customizable];
  }

  async dammPool(r: Raise) {
    return deriveDammV2PoolAddress(await this.dammConfig(), r.baseMint, r.quoteMint);
  }

  async migrate(r: Raise) {
    const m = await this.dbc.migration.migrateToDammV2({
      payer: this.payer,
      pool: r.pool,
      dammConfig: await this.dammConfig(),
    });
    const sig = await this.net.send("migrate_damm_v2", m.transaction.instructions, [
      m.firstPositionNftKeypair,
      m.secondPositionNftKeypair,
    ]);
    return { sig, nftMints: [m.firstPositionNftKeypair.publicKey, m.secondPositionNftKeypair.publicKey] };
  }

  /** De las posiciones creadas al migrar, devuelve la que pertenece a la tesorería. */
  async treasuryPosition(r: Raise, nftMints: PublicKey[]) {
    for (const mint of nftMints) {
      const nftAccount = PublicKey.findProgramAddressSync([Buffer.from("position_nft_account"), mint.toBuffer()], DAMM_V2)[0];
      const info = await this.net.conn.getAccountInfo(nftAccount);
      if (info && new PublicKey(info.data.subarray(32, 64)).equals(r.treasury)) {
        const position = PublicKey.findProgramAddressSync([Buffer.from("position"), mint.toBuffer()], DAMM_V2)[0];
        return { nftMint: mint, nftAccount, position };
      }
    }
    throw new Error("Ninguna posición de DAMM v2 pertenece a la tesorería");
  }

  async claimLpFees(r: Raise, pos: { nftAccount: PublicKey; position: PublicKey }) {
    const pool = await this.dammPool(r);
    const ix = await this.m
      .claimLpFees()
      .accountsStrict({
        raise: r.raise,
        treasury: r.treasury,
        treasuryBase: r.treasuryBase,
        treasuryQuote: r.treasuryQuote,
        baseMint: r.baseMint,
        quoteMint: r.quoteMint,
        dammPoolAuthority: deriveDammV2PoolAuthority(),
        dammPool: pool,
        position: pos.position,
        dammBaseVault: deriveDammV2TokenVaultAddress(pool, r.baseMint),
        dammQuoteVault: deriveDammV2TokenVaultAddress(pool, r.quoteMint),
        positionNftAccount: pos.nftAccount,
        dammEventAuthority: deriveDammV2EventAuthority(),
        dammProgram: DAMM_V2,
        baseTokenProgram: TOKEN_2022_PROGRAM_ID,
        quoteTokenProgram: r.quoteProgram,
      })
      .instruction();
    return this.net.send("claim_lp_fees", [...this.ensureTreasuryAtas(r), ix], []);
  }

  // ---------------------------------------------------------------- piso de precio
  /** Estado del pool DAMM v2 graduado: reservas y precio (lamports por unidad base). */
  async dammState(r: Raise) {
    const damm = createDammV2Program(this.net.conn) as any;
    const pool = await this.dammPool(r);
    const info = await this.net.conn.getAccountInfo(pool);
    if (!info) return null;
    const p = damm.coder.accounts.decode("pool", info.data);
    const sqrt = BigInt(p.sqrtPrice.toString());
    // precio = (sqrt / 2^64)^2 en unidades atómicas (lamports por unidad base)
    const price = Number((sqrt * sqrt) >> 64n) / 2 ** 64;
    return {
      pool,
      baseReserve: new BN(p.tokenAAmount.toString()),
      quoteReserve: new BN(p.tokenBAmount.toString()),
      price,
    };
  }

  /** Respaldo por unidad base: lo que la tesorería tiene por cada token en circulación. */
  async backing(r: Raise) {
    const treasuryQuote = await this.tokenBalance(r.treasuryQuote);
    const circulating = (await this.mintSupply(r.baseMint)).sub(await this.tokenBalance(r.treasuryBase));
    const perUnit = circulating.isZero() ? 0 : Number(treasuryQuote.toString()) / Number(circulating.toString());
    return { treasuryQuote, circulating, perUnit };
  }

  /** Presupuesto restante para defender el piso: reserva + comisiones − gastado. */
  async floorBudget(r: Raise) {
    const raise = await r.fetch();
    const funded = new BN(raise.fundedAmount.toString());
    const reserve = funded.muln(raise.floorReserveBps).divn(10_000);
    const b = reserve.add(new BN(raise.feesCollected.toString())).sub(new BN(raise.floorSpent.toString()));
    return b.isNeg() ? new BN(0) : b;
  }

  /** SOL que conviene gastar para devolver el precio al respaldo (aprox. producto constante,
   *  descontando la comisión del pool), acotado por el presupuesto. 0 si el precio ya está arriba. */
  async suggestDefend(r: Raise): Promise<BN> {
    const st = await this.dammState(r);
    if (!st) return new BN(0);
    const { perUnit } = await this.backing(r);
    if (!(perUnit > 0) || st.price >= perUnit) return new BN(0);
    const q = Number(st.quoteReserve.toString());
    const b = Number(st.baseReserve.toString());
    const target = Math.sqrt(q * b * perUnit); // reserva de SOL con la que precio = respaldo
    const gap = Math.max(0, (target - q) * 0.9); // margen: comisión y redondeos
    const budget = await this.floorBudget(r);
    return BN.min(new BN(Math.floor(gap).toString()), budget);
  }

  async defendFloor(r: Raise, amountIn: BN) {
    const pool = await this.dammPool(r);
    const ix = await this.m
      .defendFloor(amountIn)
      .accountsStrict({
        raise: r.raise,
        treasury: r.treasury,
        treasuryBase: r.treasuryBase,
        treasuryQuote: r.treasuryQuote,
        baseMint: r.baseMint,
        quoteMint: r.quoteMint,
        dammPoolAuthority: deriveDammV2PoolAuthority(),
        dammPool: pool,
        dammBaseVault: deriveDammV2TokenVaultAddress(pool, r.baseMint),
        dammQuoteVault: deriveDammV2TokenVaultAddress(pool, r.quoteMint),
        dammEventAuthority: deriveDammV2EventAuthority(),
        dammProgram: DAMM_V2,
        baseTokenProgram: TOKEN_2022_PROGRAM_ID,
        quoteTokenProgram: r.quoteProgram,
      })
      .instruction();
    return this.net.send("defend_floor", [...this.ensureTreasuryAtas(r), ix], []);
  }

  /** Swap token→SOL en DAMM v2 (para tests y demo: empujar el precio hacia abajo). */
  async dammSell(r: Raise, baseIn: BN, seller = this.net.payer) {
    const damm = createDammV2Program(this.net.conn) as any;
    const pool = await this.dammPool(r);
    const wsol = r.quoteAta(seller.publicKey);
    const ixs = [
      createAssociatedTokenAccountIdempotentInstruction(seller.publicKey, wsol, seller.publicKey, r.quoteMint, r.quoteProgram),
      await damm.methods
        .swap({ amountIn: baseIn, minimumAmountOut: new BN(0) })
        .accountsPartial({
          poolAuthority: deriveDammV2PoolAuthority(),
          pool,
          inputTokenAccount: r.baseAta(seller.publicKey),
          outputTokenAccount: wsol,
          tokenAVault: deriveDammV2TokenVaultAddress(pool, r.baseMint),
          tokenBVault: deriveDammV2TokenVaultAddress(pool, r.quoteMint),
          tokenAMint: r.baseMint,
          tokenBMint: r.quoteMint,
          payer: seller.publicKey,
          tokenAProgram: TOKEN_2022_PROGRAM_ID,
          tokenBProgram: r.quoteProgram,
          referralTokenAccount: null,
          eventAuthority: deriveDammV2EventAuthority(),
          program: DAMM_V2,
        })
        .instruction(),
    ];
    return this.net.send("venta en DAMM v2", ixs, [seller]);
  }

  /** Swap SOL→token en el pool DAMM v2 graduado (genera comisiones de LP). */
  async dammBuy(r: Raise, lamportsIn: BN, buyer = this.net.payer) {
    const damm = createDammV2Program(this.net.conn) as any;
    const pool = await this.dammPool(r);
    const wsol = r.quoteAta(buyer.publicKey);
    const out = r.baseAta(buyer.publicKey);
    const ixs = [
      createAssociatedTokenAccountIdempotentInstruction(buyer.publicKey, wsol, buyer.publicKey, r.quoteMint, r.quoteProgram),
      createAssociatedTokenAccountIdempotentInstruction(buyer.publicKey, out, buyer.publicKey, r.baseMint, TOKEN_2022_PROGRAM_ID),
      // con SOL hay que envolverlo en wSOL; otras monedas salen directamente de la cuenta del comprador
      ...(r.isSol
        ? [
            SystemProgram.transfer({ fromPubkey: buyer.publicKey, toPubkey: wsol, lamports: BigInt(lamportsIn.toString()) }),
            createSyncNativeInstruction(wsol),
          ]
        : []),
      await damm.methods
        .swap({ amountIn: lamportsIn, minimumAmountOut: new BN(0) })
        .accountsPartial({
          poolAuthority: deriveDammV2PoolAuthority(),
          pool,
          inputTokenAccount: wsol,
          outputTokenAccount: out,
          tokenAVault: deriveDammV2TokenVaultAddress(pool, r.baseMint),
          tokenBVault: deriveDammV2TokenVaultAddress(pool, r.quoteMint),
          tokenAMint: r.baseMint,
          tokenBMint: r.quoteMint,
          payer: buyer.publicKey,
          tokenAProgram: TOKEN_2022_PROGRAM_ID,
          tokenBProgram: r.quoteProgram,
          referralTokenAccount: null,
          eventAuthority: deriveDammV2EventAuthority(),
          program: DAMM_V2,
        })
        .instruction(),
    ];
    return this.net.send("swap en DAMM v2", ixs, [buyer]);
  }

  // ---------------------------------------------------------------- gobernanza
  async propose(r: Raise, team = this.net.payer, ev?: Evidence) {
    const e = ev ?? (await evidence("https://github.com/Zyxel89/owncurve/blob/main/docs/MILESTONES.md"));
    const ix = await this.m
      .proposeRelease(e.uri, e.hash)
      .accountsStrict({ team: team.publicKey, raise: r.raise })
      .instruction();
    return this.net.send("propose_release", [ix], [team]);
  }

  async reject(r: Raise, voter: Keypair, amount: BN) {
    const raise = await r.fetch();
    const ix = await this.m
      .reject(amount)
      .accountsStrict({
        voter: voter.publicKey,
        raise: r.raise,
        vote: r.voteRecord(voter.publicKey, raise.proposalNonce),
        escrow: r.escrow,
        escrowBase: r.escrowBase,
        voterBase: r.baseAta(voter.publicKey),
        baseMint: r.baseMint,
        baseTokenProgram: TOKEN_2022_PROGRAM_ID,
        systemProgram: SystemProgram.programId,
      })
      .instruction();
    const ata = createAssociatedTokenAccountIdempotentInstruction(
      this.payer,
      r.escrowBase,
      r.escrow,
      r.baseMint,
      TOKEN_2022_PROGRAM_ID,
    );
    return this.net.send("reject", [ata, ix], [voter]);
  }

  async finalize(r: Raise) {
    const raise = await r.fetch();
    const teamQuote = r.quoteAta(raise.team);
    const ix = await this.m
      .finalize()
      .accountsStrict({
        raise: r.raise,
        treasury: r.treasury,
        treasuryQuote: r.treasuryQuote,
        treasuryBase: r.treasuryBase,
        teamQuote,
        quoteMint: r.quoteMint,
        baseMint: r.baseMint,
        quoteTokenProgram: r.quoteProgram,
        budget: r.budget,
      })
      .instruction();
    return this.net.send(
      "finalize",
      [
        ...this.ensureTreasuryAtas(r),
        createAssociatedTokenAccountIdempotentInstruction(this.payer, teamQuote, raise.team, r.quoteMint, r.quoteProgram),
        ix,
      ],
      [],
    );
  }

  async withdrawVote(r: Raise, voter: Keypair, nonce: number) {
    const ix = await this.m
      .withdrawVote()
      .accountsStrict({
        voter: voter.publicKey,
        raise: r.raise,
        vote: r.voteRecord(voter.publicKey, nonce),
        escrow: r.escrow,
        escrowBase: r.escrowBase,
        voterBase: r.baseAta(voter.publicKey),
        baseMint: r.baseMint,
        baseTokenProgram: TOKEN_2022_PROGRAM_ID,
      })
      .instruction();
    return this.net.send("withdraw_vote", [ix], [voter]);
  }

  async redeem(r: Raise, holder: Keypair, amount: BN) {
    const holderQuote = r.quoteAta(holder.publicKey);
    const ix = await this.m
      .redeem(amount)
      .accountsStrict({
        holder: holder.publicKey,
        raise: r.raise,
        treasury: r.treasury,
        treasuryQuote: r.treasuryQuote,
        treasuryBase: r.treasuryBase,
        holderBase: r.baseAta(holder.publicKey),
        holderQuote,
        baseMint: r.baseMint,
        quoteMint: r.quoteMint,
        baseTokenProgram: TOKEN_2022_PROGRAM_ID,
        quoteTokenProgram: r.quoteProgram,
      })
      .instruction();
    return this.net.send(
      "redeem",
      [
        ...this.ensureTreasuryAtas(r),
        createAssociatedTokenAccountIdempotentInstruction(this.payer, holderQuote, holder.publicKey, r.quoteMint, r.quoteProgram),
        ix,
      ],
      [holder],
    );
  }

  // ---------------------------------------------------------------- utilidades
  async tokenBalance(ata: PublicKey): Promise<BN> {
    const info = await this.net.conn.getAccountInfo(ata);
    // Cuenta inexistente o cerrada (p. ej. wSOL tras unwrap) ⇒ saldo 0.
    return info && info.data.length >= 72 ? new BN(info.data.readBigUInt64LE(64).toString()) : new BN(0);
  }

  async mintSupply(mint: PublicKey): Promise<BN> {
    const info = await this.net.conn.getAccountInfo(mint);
    return new BN(info!.data.readBigUInt64LE(36).toString());
  }

  async transferBase(r: Raise, from: Keypair, to: PublicKey, amount: BN) {
    const dst = r.baseAta(to);
    return this.net.send(
      "transferir tokens",
      [
        createAssociatedTokenAccountIdempotentInstruction(this.payer, dst, to, r.baseMint, TOKEN_2022_PROGRAM_ID),
        createTransferCheckedInstruction(
          r.baseAta(from.publicKey),
          r.baseMint,
          dst,
          from.publicKey,
          BigInt(amount.toString()),
          BASE_DECIMALS,
          [],
          TOKEN_2022_PROGRAM_ID,
        ),
      ],
      [from],
    );
  }
}
