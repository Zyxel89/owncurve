// Mainnet study: what do Meteora DBC launches promise holders today?
//
// Reads every DBC config and counts the launches (virtual pools) that use each one, straight from
// Solana mainnet, then measures the protections OwnCurve enforces on-chain:
//   · Where the graduation (migration) fee goes: a wallet, or a program (PDA)?
//   · Can someone withdraw the graduated liquidity (unlocked partner/creator LP)?
//   · Does someone keep the mint authority?
//
//   MAINNET_RPC=https://... npx tsx scripts/study.ts        (needs getProgramAccounts on mainnet)
//
// Output: docs/MAINNET-STUDY.md and docs/mainnet-study.json
import { Connection, PublicKey } from "@solana/web3.js";
import bs58 from "bs58";
import fs from "fs";

const DBC = new PublicKey("dbcij3LWUppWqq96dh6gJWwBifmcGfLSB5D4DuSMaqN");
const POOL_DISC = Buffer.from("d5e005d16245775c", "hex"); // VirtualPool
const CONFIG_DISC = Buffer.from("1a6c0e7b74e6812b", "hex"); // PoolConfig
const POOL_CONFIG_OFFSET = 72; // VirtualPool.config
const QUOTES: Record<string, string> = {
  So11111111111111111111111111111111111111112: "SOL",
  EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v: "USDC",
  Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB: "USDT",
};
const MINT_AUTHORITY_KEPT = new Set([3, 4]); // CreatorUpdateAndMintAuthority, PartnerUpdateAndMintAuthority

const pct = (a: number, b: number) => (b ? (100 * a) / b : 0);
const f1 = (x: number) => x.toFixed(1);

async function withRetry<T>(label: string, fn: () => Promise<T>, tries = 4): Promise<T> {
  let last: unknown;
  for (let i = 0; i < tries; i++) {
    try {
      return await fn();
    } catch (e) {
      last = e;
      await new Promise((r) => setTimeout(r, 1500 * (i + 1)));
    }
  }
  throw new Error(`${label}: ${String((last as any)?.message ?? last).slice(0, 200)}`);
}

async function main() {
  const url = process.env.MAINNET_RPC;
  if (!url) throw new Error("Set MAINNET_RPC to a mainnet RPC that allows getProgramAccounts");
  const conn = new Connection(url, { commitment: "confirmed", disableRetryOnRateLimit: false });
  const slot = await conn.getSlot();
  console.log(`  slot ${slot}`);

  // 1. Configs: only the bytes we need (dataSlice) and sharded by the first byte of fee_claimer,
  //    because mainnet has hundreds of thousands of DBC configs (one per launch on many launchpads).
  console.log("  … reading every DBC config (256 shards)");
  type Cfg = {
    address: string;
    feeClaimer: string;
    feeClaimerIsProgram: boolean;
    migrationFeePct: number;
    creatorShareOfFeePct: number;
    unlockedLpPct: number;
    mintAuthorityKept: boolean;
    quote: string;
    launches: number;
  };
  const configs = new Map<string, Cfg>();
  const SLICE_FROM = 8; // PoolConfig, Meteora DBC IDL offsets
  const SLICE_LEN = 241; // quote_mint … creator_migration_fee_percentage
  const parseConfig = (address: string, d: Buffer) => {
    const at = (off: number) => (d.length >= 1048 ? off : off - SLICE_FROM); // a local RPC may ignore dataSlice
    const pk = (off: number) => new PublicKey(d.subarray(at(off), at(off) + 32));
    const u8 = (off: number) => d[at(off)];
    const feeClaimer = pk(40);
    const qm = pk(8).toBase58();
    configs.set(address, {
      address,
      feeClaimer: feeClaimer.toBase58(),
      feeClaimerIsProgram: !PublicKey.isOnCurve(feeClaimer.toBytes()),
      migrationFeePct: u8(247),
      creatorShareOfFeePct: u8(248),
      unlockedLpPct: u8(240) + u8(242), // partner + creator liquidity (unlocked)
      mintAuthorityKept: MINT_AUTHORITY_KEPT.has(u8(246)),
      quote: QUOTES[qm] ?? "other",
      launches: 0,
    });
  };
  const runShards = async (label: string, fetchShard: (b: number) => Promise<void>) => {
    const shards = Array.from({ length: 256 }, (_, b) => b);
    let done = 0;
    const worker = async () => {
      for (;;) {
        const b = shards.shift();
        if (b === undefined) return;
        await withRetry(`${label} shard ${b}`, () => fetchShard(b), 6);
        if (++done % 32 === 0) console.log(`    ${label}: ${done}/256 shards`);
      }
    };
    await Promise.all(Array.from({ length: Number(process.env.STUDY_CONCURRENCY ?? 4) }, worker));
  };
  await runShards("configs", async (b) => {
    const rows = await conn.getProgramAccounts(DBC, {
      dataSlice: { offset: SLICE_FROM, length: SLICE_LEN },
      filters: [
        { dataSize: 1048 },
        { memcmp: { offset: 0, bytes: bs58.encode(CONFIG_DISC) } },
        { memcmp: { offset: 40, bytes: bs58.encode(Uint8Array.from([b])) } },
      ],
    });
    for (const { pubkey, account } of rows) parseConfig(pubkey.toBase58(), account.data);
  });
  console.log(`  ${configs.size.toLocaleString("en-US")} configs`);

  // 2. Launches per config: VirtualPool.config only, sharded by its first byte
  console.log("  … counting launches per config (256 shards)");
  let launches = 0;
  let unknown = 0;
  await runShards("launches", async (b) => {
    const rows = await conn.getProgramAccounts(DBC, {
      dataSlice: { offset: POOL_CONFIG_OFFSET, length: 32 },
      filters: [
        { memcmp: { offset: 0, bytes: bs58.encode(POOL_DISC) } },
        { memcmp: { offset: POOL_CONFIG_OFFSET, bytes: bs58.encode(Uint8Array.from([b])) } },
      ],
    });
    for (const { account } of rows) {
      const d = account.data;
      const key = new PublicKey(d.length === 32 ? d : d.subarray(POOL_CONFIG_OFFSET, POOL_CONFIG_OFFSET + 32)).toBase58();
      const c = configs.get(key);
      launches++;
      if (c) c.launches++;
      else unknown++;
    }
  });

  // 3. Metrics, by config and weighted by launches
  const all = [...configs.values()];
  const counted = all.reduce((a, c) => a + c.launches, 0);
  const metric = (pred: (c: Cfg) => boolean) => ({
    configs: all.filter(pred).length,
    configsPct: pct(all.filter(pred).length, all.length),
    launches: all.filter(pred).reduce((a, c) => a + c.launches, 0),
    launchesPct: pct(all.filter(pred).reduce((a, c) => a + c.launches, 0), counted),
  });
  const ownCurveGrade = (c: Cfg) => c.feeClaimerIsProgram && c.unlockedLpPct === 0 && !c.mintAuthorityKept && c.creatorShareOfFeePct === 0;
  const m = {
    feeToWallet: metric((c) => c.migrationFeePct > 0 && !c.feeClaimerIsProgram),
    feeToProgram: metric((c) => c.migrationFeePct > 0 && c.feeClaimerIsProgram),
    feeAtLeast50: metric((c) => c.migrationFeePct >= 50),
    unlockedLp: metric((c) => c.unlockedLpPct > 0),
    mintAuthorityKept: metric((c) => c.mintAuthorityKept),
    ownCurveGrade: metric(ownCurveGrade),
    quoteSol: metric((c) => c.quote === "SOL"),
    quoteStable: metric((c) => c.quote === "USDC" || c.quote === "USDT"),
    quoteOther: metric((c) => c.quote === "other"),
  };
  const weightedFee = counted ? all.reduce((a, c) => a + c.migrationFeePct * c.launches, 0) / counted : 0;
  const top = [...all].sort((a, b) => b.launches - a.launches).slice(0, 10);

  const result = { generatedAt: new Date().toISOString(), slot, configs: all.length, launches, launchesWithKnownConfig: counted, unknownConfigLaunches: unknown, weightedMigrationFeePct: weightedFee, metrics: m, topConfigs: top };
  fs.mkdirSync("docs", { recursive: true });
  fs.writeFileSync("docs/mainnet-study.json", JSON.stringify(result, null, 2));

  const row = (label: string, x: (typeof m)[keyof typeof m]) =>
    `| ${label} | ${x.configs.toLocaleString("en-US")} (${f1(x.configsPct)}%) | ${x.launches.toLocaleString("en-US")} (${f1(x.launchesPct)}%) |`;
  const md = [
    `# Mainnet study · what Meteora DBC launches promise holders`,
    ``,
    `Read directly from Solana mainnet at slot ${slot} (${result.generatedAt.slice(0, 10)}) with \`scripts/study.ts\`: every DBC config, and every launch (virtual pool) counted against the config it uses. Raw numbers: [\`mainnet-study.json\`](mainnet-study.json).`,
    ``,
    `**${all.length.toLocaleString("en-US")} configs · ${launches.toLocaleString("en-US")} launches.** Launch-weighted average graduation (migration) fee: **${f1(weightedFee)}%** of the raise.`,
    ``,
    `| At graduation… | Configs | Launches |`,
    `| --- | --- | --- |`,
    row("the migration fee is paid to a **wallet** (fee_claimer is a normal key)", m.feeToWallet),
    row("the migration fee is paid to a **program** (fee_claimer is a PDA)", m.feeToProgram),
    row("≥ 50% of the raise is taken as migration fee", m.feeAtLeast50),
    row("part of the graduated **LP is unlocked** (can be withdrawn)", m.unlockedLp),
    row("someone **keeps the mint authority**", m.mintAuthorityKept),
    row("**all four OwnCurve guarantees hold** (PDA fee claimer, 0% to creator, no unlocked LP, no mint authority)", m.ownCurveGrade),
    ``,
    `Raised in: SOL ${f1(m.quoteSol.launchesPct)}% · USDC/USDT ${f1(m.quoteStable.launchesPct)}% · other tokens ${f1(m.quoteOther.launchesPct)}% of launches.`,
    ``,
    `## Most used configs`,
    ``,
    `| Config | Launches | Migration fee | Fee goes to | Unlocked LP | Mint authority kept |`,
    `| --- | --- | --- | --- | --- | --- |`,
    ...top.map(
      (c) =>
        `| [\`${c.address.slice(0, 6)}…\`](https://solscan.io/account/${c.address}) | ${c.launches.toLocaleString("en-US")} | ${c.migrationFeePct}% | ${c.feeClaimerIsProgram ? "program" : "wallet"} | ${c.unlockedLpPct}% | ${c.mintAuthorityKept ? "yes" : "no"} |`,
    ),
    ``,
    `## Why it matters for OwnCurve`,
    ``,
    `OwnCurve's \`bind_pool\` refuses any config that does not route the migration fee to its treasury PDA, gives the creator a share of it, leaves LP unlocked or keeps a mint authority. The table shows how rare that combination is today, and that wherever a large migration fee exists it almost always lands in a wallet: exactly the money OwnCurve keeps in escrow and releases per milestone.`,
    ``,
    `Method notes: "wallet" means the fee_claimer key is on the ed25519 curve (it has a private key); a PDA can only be moved by its program. The migration fee is the share of the raise taken at graduation before the rest becomes DAMM liquidity; it is split between the fee_claimer and the creator by \`creatorMigrationFeePercentage\`.`,
    ``,
  ].join("\n");
  fs.writeFileSync("docs/MAINNET-STUDY.md", md);
  console.log(`\n  ${all.length} configs · ${launches} launches · fee to a wallet in ${f1(m.feeToWallet.launchesPct)}% of launches · OwnCurve-grade ${f1(m.ownCurveGrade.launchesPct)}%`);
  console.log("  docs/MAINNET-STUDY.md");
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error(`  ✘ ${e.message ?? e}`);
    process.exit(1);
  });
