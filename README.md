# OwnCurve

Ownership coins on Meteora's Dynamic Bonding Curve (DBC).

A raise is a normal DBC launch whose config names OwnCurve's treasury PDA as
`fee_claimer` and `leftover_receiver`. At graduation the DBC migration fee (up to
99% of the raise) is pulled into an on-chain treasury instead of a wallet. The team
is paid in milestone tranches; holders can lock tokens to reject a tranche, and a
rejection that reaches quorum turns the treasury into a pro-rata redemption pool.
After graduation the treasury also owns the DAMM v2 LP position, so it keeps earning
trading fees forever.

Five things no other launchpad does on-chain:

- **Evidence-backed milestones.** Every tranche request stores a link to the delivered work and
  the SHA-256 of what the team claims it shipped. Holders (or their AI agent) review it during
  the challenge window.
- **A price floor that defends itself.** A share of the treasury (default 20%) plus every fee it
  earns is never paid to the team. When the token trades on DAMM v2 below what the treasury
  holds per token, anyone can call `defend_floor`: the treasury buys tokens back through a CPI
  swap, **the program refuses to pay more than the backing**, and the tokens are burned, so the
  backing of every remaining token goes up.
- **Meteora Bedrock's takeover clause, enforced by the program.** Bedrock protects holders
  legally: an acquirer must buy everyone out at TWAP +30%. OwnCurve makes it code: the program
  keeps its own TWAP from DAMM v2 price observations, and the only way to take a raise over is
  `tender_offer`, which tops the treasury up until every circulating token redeems at
  TWAP × (1 + premium). The acquirer becomes the team; holders redeem.
- **A ghost-team switch.** If the team goes `inactivity` without requesting a tranche, anyone can
  call `declare_abandoned` and the treasury becomes a redemption pool. Nobody has to vote.
- **Raise in anything.** SOL, a stablecoin like USDC (SPL) or a tokenized stock like the xStocks
  (Token-2022): the program is token-interface generic, so the treasury, tranches, redemptions and
  floor buybacks all work in the raise currency.

Plus a **rug check** for any Meteora launch: paste a mainnet token and see, from its on-chain DBC
config, whether the raise goes to a wallet, the creator takes a cut, liquidity can be pulled or more
tokens can be minted.

And it is built for agents: an **MCP server** and an **Agent Skill** let any AI client read raises,
audit milestone evidence and act for holders, with every write simulated unless confirmed.

Built for the Colosseum Crypto World's Fair — "Best use of Meteora's DBC" sidetrack.

## Why: Meteora DBC on mainnet today

We read every Meteora DBC config (534,981) and launch (1,738,512) on mainnet
([`docs/MAINNET-STUDY.md`](docs/MAINNET-STUDY.md)):

- **63.6%** of launches let a partner or creator **withdraw graduated liquidity**. OwnCurve: 0%.
- Only **10.1%** meet four basic holder guarantees (program-controlled fee, no creator cut, locked LP,
  no mint authority). Every OwnCurve raise meets them, enforced by `bind_pool`.
- **3.8%** pay a graduation fee straight to a wallet; OwnCurve routes it to a treasury that pays per milestone.

## Try it

- **Live app (Solana devnet):** https://zyxel89.github.io/owncurve/ — click **Use a test wallet**, or connect Phantom / Solflare / Backpack set to devnet.
- **A raise that paid its team in 3 evidence-backed tranches and defended its price floor:** https://zyxel89.github.io/owncurve/#/raise/7sDbgBXGy6o5AWs6NpCUG8EfuRCTBqzKG8SNZ8Prb7Ra
- **A raise whose holders stopped the payment and redeemed the treasury:** https://zyxel89.github.io/owncurve/#/raise/ERrfcHfstYDDgamvvRYS3XDkJ2LmZk8Dei6sMhSQV9tW
- **A raise in a stablecoin (tUSD, SPL like USDC):** https://zyxel89.github.io/owncurve/#/raise/FLtDebR8xRPrLcmGTDwA1XSfn3JbFw9ts5APNrDEQW3m
- **A raise in a tokenized stock (tNVDAx, Token-2022 like xStocks) that defended its floor:** https://zyxel89.github.io/owncurve/#/raise/FDtBpfVYe1NJKNWWiuieJueFPKfmDY6XJhJyRxjc1aQe
- **A raise taken over through the on-chain Bedrock clause (holders paid TWAP +30%):** https://zyxel89.github.io/owncurve/#/raise/8toF88iSKFRstDfZzsRNkHz2GBet84K5ztgBEkXyFXNN
- **A raise whose team went silent, so the treasury went back to holders:** https://zyxel89.github.io/owncurve/#/raise/DVW29fmVR36A65xViVbuJNTzMMAvJro8vm4tpvX7MimF
- **Rug check any Meteora launch (mainnet):** https://zyxel89.github.io/owncurve/#/scan
- **Mainnet study, what DBC launches promise holders today:** [`docs/MAINNET-STUDY.md`](docs/MAINNET-STUDY.md)
- **Every devnet transaction, step by step:** [`docs/DEMO-devnet.md`](docs/DEMO-devnet.md)
- **Agent Skill and MCP server:** [`skills/owncurve/SKILL.md`](skills/owncurve/SKILL.md) · [`scripts/mcp.ts`](scripts/mcp.ts)
- **Security notes and binary verification:** [`SECURITY.md`](SECURITY.md)

```
OwnCurve program (Anchor 1.2)                Meteora
┌──────────────────────────────┐   CPI   ┌───────────────────────────────┐
│ Raise + treasury PDA         │ ──────▶ │ DBC: withdraw_migration_fee,  │
│  tranches · objections       │         │      claim_trading_fee,        │
│  floor reserve · evidence    │         │      partner_withdraw_surplus  │
│                              │ ──────▶ │ DAMM v2: claim_position_fee,  │
│ defend_floor: buy ≤ backing, │         │          swap (buyback)        │
│ then burn                    │         └───────────────────────────────┘
└──────────────────────────────┘
```

## Lifecycle

```
Pending --bind_pool--> Bonding --harvest (CPI)--> Funded
Funded --propose_release(evidence) + reject votes--> finalize
    quorum not reached -> tranche to team -> Funded (next milestone) / Completed (last)
    quorum reached     -> Liquidating -> redeem (burn tokens, receive NAV share)
Any time after launch: collect_trading_fees, collect_surplus, claim_lp_fees -> treasury
After graduation, price < backing: defend_floor -> DAMM v2 swap (treasury pays) -> burn
Guard (optional account, set at launch):
    Funded + team silent for `inactivity` -> declare_abandoned -> Liquidating
    observe (DAMM v2 price) x N -> TWAP -> tender_offer (pay holders TWAP + premium) -> Liquidating, team = acquirer
```

## Instructions

| Instruction | Caller | What it does |
| --- | --- | --- |
| `init_raise` | team | Milestone tranches (sum 10000 bps), min treasury %, challenge window, reject quorum, floor reserve (≤ 50%) |
| `bind_pool` | anyone | Validates the live DBC config + pool before anyone buys (see guarantees) |
| `harvest` | anyone | CPI `withdraw_migration_fee` signed by the treasury PDA |
| `collect_trading_fees` | anyone | CPI `claim_trading_fee`: partner share of curve fees → treasury |
| `collect_surplus` | anyone | CPI `partner_withdraw_surplus` → treasury |
| `claim_lp_fees` | anyone | CPI DAMM v2 `claim_position_fee` for the treasury-owned position |
| `propose_release` | team | Opens a challenge window for the next milestone, with evidence URL + SHA-256 |
| `reject` | holder | Locks base tokens in escrow as a reject vote |
| `finalize` | anyone | Pays the tranche, or switches to liquidation if quorum was met |
| `withdraw_vote` | holder | Returns locked tokens after finalize |
| `redeem` | holder | In liquidation: burn tokens, receive a pro-rata share of the treasury |
| `init_guard` | team | Ghost-team window, takeover premium and TWAP window (before funding) |
| `arm_guard` | anyone | Starts the inactivity clock (bundled with `harvest`) |
| `declare_abandoned` | anyone | Team silent past the window → treasury becomes a redemption pool |
| `observe` | anyone | Records the DAMM v2 price (owner, discriminator and mints checked) into the guard's TWAP ring |
| `tender_offer` | anyone | Takeover: deposit until every token redeems at TWAP × (1 + premium); acquirer becomes team |
| `defend_floor` | anyone | CPI DAMM v2 `swap` paid by the treasury, only at or below backing; bought tokens are burned |

## On-chain guarantees (enforced by `bind_pool` / `init_raise`)

- `fee_claimer` and `leftover_receiver` of the DBC config are the treasury PDA: only this program can move the raise.
- The creator gets 0% of the migration fee and its DAMM v2 LP is 100% permanently locked (no liquidity rug).
- The creator never holds the mint authority (no infinite mint).
- The migration fee routed to the treasury is at least the raise's `min_treasury_pct` (≥ 50%).
- Holders always get a challenge window of ≥ 60 s, and blocking a tranche never needs more than 30% of supply.
- Fees, surplus and LP fees can only be sent to treasury-owned token accounts.
- Tranches pay at most `funded − floor reserve`; the floor budget (reserve + fees) can only buy back at or below backing.

## Verified against DBC source (program 0.2.1, commit f552f20)

- `MAX_MIGRATION_FEE_PERCENTAGE = 99`; `create_config` takes `fee_claimer` as an unchecked account, so it can be a PDA.
- `withdraw_migration_fee`, `claim_trading_fee` and `partner_withdraw_surplus` require `fee_claimer` as signer.
- On DAMM v2 migration the partner position is minted to `config.fee_claimer` (the treasury).

## Devnet

Program `GBHTxatkmbAX5U7G65yXzDVAZjjjyW9btGZ1DNUHtcfh`. `scripts/demo.ts` runs six real raises:
evidence-backed tranches with a defended floor (SOL), a rejected tranche that ends in redemptions
(SOL), a raise in a stablecoin (tUSD) and a raise in a tokenized stock (tNVDAx) that defends its
floor, a raise taken over through the on-chain Bedrock clause, and a raise whose silent team lost
the treasury to its holders. Every transaction is linked in [`docs/DEMO-devnet.md`](docs/DEMO-devnet.md).

## Web app

`app/` is a Vite + React front end that reuses the same client as the scripts (`scripts/lib/owncurve.ts`).
It lists every raise, draws the treasury as a vault split into tranches, shows the guarantees that
`bind_pool` checked on-chain, and lets anyone buy, object, settle and redeem. Connect a browser wallet
(Phantom, Solflare, Backpack…) or click **Use a test wallet** to try it on devnet without installing anything.

```
npm run app            # http://localhost:5173 (devnet; set VITE_RPC_URL in app/.env.local)
npm run e2e            # Chromium drives the whole lifecycle against LiteSVM with the real programs
```

## Raise in SOL, stablecoins or tokenized stocks

Every account that touches the raise currency is an `InterfaceAccount` with its own token program,
so a raise can be quoted in SOL, any SPL token or any Token-2022 token that Meteora DBC and DAMM v2
accept. On devnet the app ships two test currencies with a public faucet (their mint authority is
deliberately public): **tUSD** (SPL, 6 decimals, like USDC) and **tNVDAx** (Token-2022, 8 decimals,
like the xStocks). On mainnet you pass the real mint (`--quote EPjF…Dt1v` for USDC).
`tests/owncurve.test.ts` runs the whole lifecycle in both (tranches, floor buyback, liquidation and
redemption).

## MCP server

```json
{
  "mcpServers": {
    "owncurve": {
      "command": "npx",
      "args": ["tsx", "/path/to/owncurve/scripts/mcp.ts"],
      "env": { "RPC_URL": "https://api.devnet.solana.com", "WALLET": "/path/to/devnet-keypair.json" }
    }
  }
}
```

16 tools (`owncurve_list`, `owncurve_show`, `owncurve_launch`, `owncurve_propose`, `owncurve_object`,
`owncurve_settle`, `owncurve_redeem`, `owncurve_defend_floor`…). Reads are annotated read-only;
writes take `confirm` and only **simulate** the transaction unless `confirm: true`.
`tests/mcp.test.ts` drives it with the official MCP client.

## Agent Skill and CLI

[`skills/owncurve/SKILL.md`](skills/owncurve/SKILL.md) teaches any AI agent that supports Agent
Skills to launch and govern raises: read a raise, check the evidence of a pending tranche,
object on the holder's behalf, settle, redeem and defend the floor. It drives
`scripts/cli.ts`, which prints JSON and **simulates every write unless `--yes` is passed**.

```
npm run owncurve -- list
npm run owncurve -- show <config>           # includes "can": the actions this wallet can take now
npm run owncurve -- defend-floor <config>   # dry run; add --yes to send
```

## Build and test

```
anchor build --skip-lint --tools-version v1.52 --arch v0
npm ci
CLUSTER=local npx tsx --test tests/owncurve.test.ts   # 29 integration tests, real DBC + DAMM v2 binaries
npx tsx --test tests/cli.test.ts                      # the agent CLI end to end over JSON-RPC
npx tsx --test tests/mcp.test.ts                      # the MCP server with the official MCP client
npx tsx --test tests/study.test.ts                    # the mainnet study against a local validator
npx tsx --test tests/scan.test.ts                     # the rug check (A+ for OwnCurve, D/F for a rug config)
npm run e2e                                           # Chromium drives the app, incl. floor defense
CLUSTER=local npx tsx scripts/f1.ts --migrate        # end-to-end flow in LiteSVM
npx tsx scripts/f1.ts --migrate                      # same flow on devnet
```

Local tests need `local/dynamic_bonding_curve.so` (built from DBC source at f552f20) and
`local/damm_v2.so` (DBC repo test fixture); `owncurve.sh` prepares both.

## Rug check

`#/scan` in the app (and `scripts/lib/scan.ts`) grades any Meteora DBC launch from its on-chain
config: A+ for OwnCurve raises, then down for each red flag (graduation fee to a wallet, creator cut,
unlocked LP, mint authority kept). It reads mainnet through the public RPC; looking up by token mint
needs an RPC that allows `getProgramAccounts`, otherwise paste the DBC pool.

## Mainnet study

`scripts/study.ts` reads every Meteora DBC config and launch on mainnet and measures what holders are
promised today: where the graduation fee goes (a wallet or a program), whether LP stays unlocked,
whether someone keeps the mint authority. Results: [`docs/MAINNET-STUDY.md`](docs/MAINNET-STUDY.md).

```
MAINNET_RPC=<mainnet RPC with getProgramAccounts> npx tsx scripts/study.ts
```

## Verify the deployed program

```
anchor build --skip-lint --tools-version v1.52 --arch v0
bash scripts/verify.sh https://api.devnet.solana.com   # SHA-256 of the devnet program == local build
anchor idl fetch <program id> --provider.cluster devnet  # IDL published on-chain
```

## Known limitations (MVP)

- Tokens sitting in the DBC/DAMM v2 pool count as circulating supply, so redemption pays them
  out only when someone buys them from the pool and redeems (an arbitrage floor, by design).
- Votes are locked tokens with no snapshot; flash-borrowed votes are possible but cost a round trip.

## License

MIT
