// Escáner de seguridad de cualquier lanzamiento de Meteora DBC (mainnet o devnet): lee la config
// del lanzamiento y comprueba las mismas garantías que OwnCurve impone en `bind_pool`.
import { DynamicBondingCurveClient } from "@meteora-ag/dynamic-bonding-curve-sdk";
import { TOKEN_2022_PROGRAM_ID, TOKEN_PROGRAM_ID } from "@solana/spl-token";
import { Connection, PublicKey } from "@solana/web3.js";

export const DBC_ID = new PublicKey("dbcij3LWUppWqq96dh6gJWwBifmcGfLSB5D4DuSMaqN");
export const DAMM_V2_ID = new PublicKey("cpamdpZCGKUy5JxQXB4dcpGPiikHawvSWAd6mEn1sGG");
const POOL_SIZE = 424;
const POOL_BASE_MINT = 136;
const DAMM_TOKEN_A_MINT = 168;
const KNOWN_QUOTES: Record<string, string> = {
  So11111111111111111111111111111111111111112: "SOL",
  EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v: "USDC",
  Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB: "USDT",
};

export type Check = { id: string; ok: boolean; warn?: boolean; title: string; detail: string };
export type ScanResult = {
  input: string;
  pool: string | null;
  config: string;
  baseMint: string | null;
  quote: string;
  ownCurve: boolean;
  grade: "A+" | "A" | "B" | "C" | "D" | "F";
  checks: Check[];
  curve: { raised: number; threshold: number; migrated: boolean } | null;
};

export async function scanLaunch(conn: Connection, address: string, ownCurveProgram?: PublicKey): Promise<ScanResult> {
  const key = new PublicKey(address.trim());
  const dbc = new DynamicBondingCurveClient(conn, "confirmed");
  const coder = (dbc.state as any).program.coder;
  const info = await conn.getAccountInfo(key);
  if (!info) throw new Error("No account at that address on this network.");

  let poolKey: PublicKey | null = null;
  let configKey: PublicKey | null = null;
  const owner = new PublicKey(info.owner);
  const findPoolByMint = async (mint: PublicKey) => {
    const rows = await conn.getProgramAccounts(DBC_ID, {
      dataSlice: { offset: 0, length: 0 },
      filters: [{ dataSize: POOL_SIZE }, { memcmp: { offset: POOL_BASE_MINT, bytes: mint.toBase58() } }],
    });
    if (!rows.length) throw new Error("That token was not launched on Meteora DBC.");
    return rows[0].pubkey;
  };

  if (owner.equals(DBC_ID)) {
    if (info.data.length === POOL_SIZE) poolKey = key;
    else configKey = key;
  } else if (owner.equals(TOKEN_PROGRAM_ID) || owner.equals(TOKEN_2022_PROGRAM_ID)) {
    try {
      poolKey = await findPoolByMint(key);
    } catch (e: any) {
      if (/not launched/.test(String(e.message))) throw e;
      throw new Error("This RPC does not allow looking a token up by mint. Paste its Meteora DBC pool address instead (Solscan shows it).");
    }
  } else if (owner.equals(DAMM_V2_ID)) {
    poolKey = await findPoolByMint(new PublicKey(info.data.subarray(DAMM_TOKEN_A_MINT, DAMM_TOKEN_A_MINT + 32)));
  } else {
    throw new Error("Paste a token mint, a Meteora DBC pool or config, or a DAMM v2 pool.");
  }

  let pool: any = null;
  if (poolKey) {
    const pinfo = poolKey.equals(key) ? info : await conn.getAccountInfo(poolKey);
    const raw = coder.accounts.decode("virtualPool", pinfo!.data);
    pool = raw.poolState ?? raw; // la SDK anida el estado en `poolState`
    configKey = new PublicKey(pool.config);
  }
  const cinfo = await conn.getAccountInfo(configKey!);
  const c = coder.accounts.decode("poolConfig", cinfo!.data);

  const feeClaimer = new PublicKey(c.feeClaimer);
  const feeToProgram = !PublicKey.isOnCurve(feeClaimer.toBytes());
  const ownCurve =
    !!ownCurveProgram &&
    feeClaimer.equals(PublicKey.findProgramAddressSync([Buffer.from("treasury"), configKey!.toBuffer()], ownCurveProgram)[0]);
  const fee = Number(c.migrationFeePercentage);
  const creatorFee = Number(c.creatorMigrationFeePercentage);
  const unlocked = Number(c.partnerLiquidityPercentage) + Number(c.creatorLiquidityPercentage);
  const vesting = Number(c.partnerLiquidityVestingInfo?.vestingPercentage ?? 0) + Number(c.creatorLiquidityVestingInfo?.vestingPercentage ?? 0);
  const mintKept = [3, 4].includes(Number(c.tokenUpdateAuthority));
  const quote = KNOWN_QUOTES[new PublicKey(c.quoteMint).toBase58()] ?? new PublicKey(c.quoteMint).toBase58().slice(0, 4) + "…";

  const checks: Check[] = [
    fee === 0
      ? { id: "fee", ok: true, title: "No graduation fee", detail: "The whole raise becomes pool liquidity at graduation." }
      : ownCurve
        ? { id: "fee", ok: true, title: `${fee}% of the raise goes to an OwnCurve treasury`, detail: "Released to the team one milestone at a time; holders can stop a payment and redeem." }
        : feeToProgram
          ? { id: "fee", ok: true, warn: true, title: `${fee}% of the raise goes to a program`, detail: `The fee claimer ${feeClaimer.toBase58().slice(0, 6)}… is a PDA: only its program can move the money. Check what that program allows.` }
          : { id: "fee", ok: false, title: `${fee}% of the raise goes to a wallet at graduation`, detail: `The fee claimer ${feeClaimer.toBase58().slice(0, 6)}… is a normal key: whoever holds it can spend that money on day one.` },
    creatorFee === 0
      ? { id: "creator-fee", ok: true, title: "The creator takes no cut of the raise", detail: "creatorMigrationFeePercentage is 0." }
      : { id: "creator-fee", ok: false, title: `The creator takes ${creatorFee}% of the graduation fee`, detail: "Paid straight to the creator's wallet when the curve graduates." },
    unlocked === 0
      ? { id: "lp", ok: true, warn: vesting > 0, title: vesting > 0 ? "Graduated liquidity is locked or vesting" : "Graduated liquidity is locked", detail: vesting > 0 ? `${vesting}% of the LP unlocks over a vesting schedule.` : "Nobody can withdraw the pool's liquidity after graduation." }
      : { id: "lp", ok: false, title: `${unlocked}% of the graduated liquidity can be withdrawn`, detail: "The partner or creator can pull that share of the pool after graduation (a liquidity rug)." },
    mintKept
      ? { id: "mint", ok: false, title: "Someone keeps the mint authority", detail: "More tokens can be printed after launch." }
      : { id: "mint", ok: true, title: "Nobody can mint more tokens", detail: "Fixed supply after launch." },
  ];
  const bad = checks.filter((x) => !x.ok).length;
  const warns = checks.filter((x) => x.ok && x.warn).length;
  const grade: ScanResult["grade"] = ownCurve && bad === 0 ? "A+" : bad === 0 ? (warns ? "B" : "A") : bad === 1 ? "C" : bad === 2 ? "D" : "F";
  let curve: ScanResult["curve"] = null;
  if (pool) {
    const dec = KNOWN_QUOTES[new PublicKey(c.quoteMint).toBase58()] === "SOL" ? 9 : (await conn.getParsedAccountInfo(new PublicKey(c.quoteMint)).then((r: any) => r.value?.data?.parsed?.info?.decimals ?? 6).catch(() => 6));
    curve = {
      raised: Number(pool.quoteReserve.toString()) / 10 ** dec,
      threshold: Number(c.migrationQuoteThreshold.toString()) / 10 ** dec,
      migrated: Boolean(pool.isMigrated),
    };
  }
  return {
    input: address.trim(),
    pool: poolKey?.toBase58() ?? null,
    config: configKey!.toBase58(),
    baseMint: pool ? new PublicKey(pool.baseMint).toBase58() : null,
    quote,
    ownCurve,
    grade,
    checks,
    curve,
  };
}

