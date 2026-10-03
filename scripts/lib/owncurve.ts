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

export type RaiseParams = {
  thresholdSol: number;
  treasuryPct: number; // % de lo recaudado que va a la tesorería (migration fee)
  tranchesBps: number[];
  challengeSecs: number;
  quorumBps: number;
  floorReserveBps: number; // parte de lo recaudado que nunca se paga: respalda el piso de precio
  // Solo para tests de seguridad: configs DBC "maliciosas".
  feeClaimer?: PublicKey;
  creatorMigrationFeePct?: number;
  creatorUnlockedLpPct?: number;
};

export const DEFAULT_PARAMS: RaiseParams = {
  thresholdSol: 0.5,
  treasuryPct: 80,
  tranchesBps: [3000, 3000, 4000],
  challengeSecs: 60,
  quorumBps: 1000,
  floorReserveBps: 2000,
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
    migrationQuoteThreshold: p.thresholdSol,
  });
}

export class Raise {
  constructor(
    readonly oc: OwnCurve,
    readonly config: PublicKey,
    readonly baseMint: PublicKey,
  ) {}
  get pid() {
    return this.oc.programId;
  }
  get raise() {
    return PublicKey.findProgramAddressSync([Buffer.from("raise"), this.config.toBuffer()], this.pid)[0];
  }
  get treasury() {
    return PublicKey.findProgramAddressSync([Buffer.from("treasury"), this.config.toBuffer()], this.pid)[0];
  }
  get escrow() {
    return PublicKey.findProgramAddressSync([Buffer.from("escrow"), this.raise.toBuffer()], this.pid)[0];
  }
  get pool() {
    return deriveDbcPoolAddress(NATIVE_MINT, this.baseMint, this.config);
  }
  get treasuryQuote() {
    return getAssociatedTokenAddressSync(NATIVE_MINT, this.treasury, true);
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
    return getAssociatedTokenAddressSync(NATIVE_MINT, owner, true);
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
      quoteMint: NATIVE_MINT,
      ...curveConfig(params),
    });
    const sig = await this.net.send("init_raise + create_config", [initRaise, ...createConfig.instructions], [
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
    const r = new Raise(this, config, baseMintKp.publicKey);
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
      createAssociatedTokenAccountIdempotentInstruction(this.payer, r.treasuryQuote, r.treasury, NATIVE_MINT),
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
        quoteMint: NATIVE_MINT,
        ...this.dbcAccounts(r, pool),
        quoteTokenProgram: TOKEN_PROGRAM_ID,
      })
      .instruction();
    return this.net.send("harvest", [...this.ensureTreasuryAtas(r), ix], []);
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
        quoteMint: NATIVE_MINT,
        ...this.dbcAccounts(r, pool),
        dbcBaseVault: pool.baseVault,
        baseTokenProgram: TOKEN_2022_PROGRAM_ID,
        quoteTokenProgram: TOKEN_PROGRAM_ID,
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
        quoteMint: NATIVE_MINT,
        ...this.dbcAccounts(r, pool),
        quoteTokenProgram: TOKEN_PROGRAM_ID,
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
    return deriveDammV2PoolAddress(await this.dammConfig(), r.baseMint, NATIVE_MINT);
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
        quoteMint: NATIVE_MINT,
        dammPoolAuthority: deriveDammV2PoolAuthority(),
        dammPool: pool,
        position: pos.position,
        dammBaseVault: deriveDammV2TokenVaultAddress(pool, r.baseMint),
        dammQuoteVault: deriveDammV2TokenVaultAddress(pool, NATIVE_MINT),
        positionNftAccount: pos.nftAccount,
        dammEventAuthority: deriveDammV2EventAuthority(),
        dammProgram: DAMM_V2,
        baseTokenProgram: TOKEN_2022_PROGRAM_ID,
        quoteTokenProgram: TOKEN_PROGRAM_ID,
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
        quoteMint: NATIVE_MINT,
        dammPoolAuthority: deriveDammV2PoolAuthority(),
        dammPool: pool,
        dammBaseVault: deriveDammV2TokenVaultAddress(pool, r.baseMint),
        dammQuoteVault: deriveDammV2TokenVaultAddress(pool, NATIVE_MINT),
        dammEventAuthority: deriveDammV2EventAuthority(),
        dammProgram: DAMM_V2,
        baseTokenProgram: TOKEN_2022_PROGRAM_ID,
        quoteTokenProgram: TOKEN_PROGRAM_ID,
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
      createAssociatedTokenAccountIdempotentInstruction(seller.publicKey, wsol, seller.publicKey, NATIVE_MINT),
      await damm.methods
        .swap({ amountIn: baseIn, minimumAmountOut: new BN(0) })
        .accountsPartial({
          poolAuthority: deriveDammV2PoolAuthority(),
          pool,
          inputTokenAccount: r.baseAta(seller.publicKey),
          outputTokenAccount: wsol,
          tokenAVault: deriveDammV2TokenVaultAddress(pool, r.baseMint),
          tokenBVault: deriveDammV2TokenVaultAddress(pool, NATIVE_MINT),
          tokenAMint: r.baseMint,
          tokenBMint: NATIVE_MINT,
          payer: seller.publicKey,
          tokenAProgram: TOKEN_2022_PROGRAM_ID,
          tokenBProgram: TOKEN_PROGRAM_ID,
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
      createAssociatedTokenAccountIdempotentInstruction(buyer.publicKey, wsol, buyer.publicKey, NATIVE_MINT),
      createAssociatedTokenAccountIdempotentInstruction(buyer.publicKey, out, buyer.publicKey, r.baseMint, TOKEN_2022_PROGRAM_ID),
      SystemProgram.transfer({ fromPubkey: buyer.publicKey, toPubkey: wsol, lamports: BigInt(lamportsIn.toString()) }),
      createSyncNativeInstruction(wsol),
      await damm.methods
        .swap({ amountIn: lamportsIn, minimumAmountOut: new BN(0) })
        .accountsPartial({
          poolAuthority: deriveDammV2PoolAuthority(),
          pool,
          inputTokenAccount: wsol,
          outputTokenAccount: out,
          tokenAVault: deriveDammV2TokenVaultAddress(pool, r.baseMint),
          tokenBVault: deriveDammV2TokenVaultAddress(pool, NATIVE_MINT),
          tokenAMint: r.baseMint,
          tokenBMint: NATIVE_MINT,
          payer: buyer.publicKey,
          tokenAProgram: TOKEN_2022_PROGRAM_ID,
          tokenBProgram: TOKEN_PROGRAM_ID,
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
    const e = ev ?? (await evidence("https://github.com/owncurve/owncurve/releases"));
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
        quoteMint: NATIVE_MINT,
        baseMint: r.baseMint,
        quoteTokenProgram: TOKEN_PROGRAM_ID,
      })
      .instruction();
    return this.net.send(
      "finalize",
      [
        ...this.ensureTreasuryAtas(r),
        createAssociatedTokenAccountIdempotentInstruction(this.payer, teamQuote, raise.team, NATIVE_MINT),
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
        quoteMint: NATIVE_MINT,
        baseTokenProgram: TOKEN_2022_PROGRAM_ID,
        quoteTokenProgram: TOKEN_PROGRAM_ID,
      })
      .instruction();
    return this.net.send(
      "redeem",
      [
        ...this.ensureTreasuryAtas(r),
        createAssociatedTokenAccountIdempotentInstruction(this.payer, holderQuote, holder.publicKey, NATIVE_MINT),
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
