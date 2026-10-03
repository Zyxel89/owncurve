# OwnCurve

Ownership coins on Meteora's Dynamic Bonding Curve (DBC).

A raise is a normal DBC launch whose config names OwnCurve's treasury PDA as
`fee_claimer` and `leftover_receiver`. At graduation the DBC migration fee (up to
99% of the raise) is pulled into an on-chain treasury instead of a wallet. The team
is paid in milestone tranches; holders can lock tokens to reject a tranche, and a
rejection that reaches quorum turns the treasury into a pro-rata redemption pool.
After graduation the treasury also owns the DAMM v2 LP position, so it keeps earning
trading fees forever.

Two things no other launchpad does on-chain:

- **Evidence-backed milestones.** Every tranche request stores a link to the delivered work and
  the SHA-256 of what the team claims it shipped. Holders (or their AI agent) review it during
  the challenge window.
- **A price floor that defends itself.** A share of the treasury (default 20%) plus every fee it
  earns is never paid to the team. When the token trades on DAMM v2 below the SOL the treasury
  holds per token, anyone can call `defend_floor`: the treasury buys tokens back through a CPI
  swap, **the program refuses to pay more than the backing**, and the tokens are burned, so the
  backing of every remaining token goes up.

Built for the Colosseum Crypto World's Fair — "Best use of Meteora's DBC" sidetrack.

## Lifecycle

```
Pending --bind_pool--> Bonding --harvest (CPI)--> Funded
Funded --propose_release(evidence) + reject votes--> finalize
    quorum not reached -> tranche to team -> Funded (next milestone) / Completed (last)
    quorum reached     -> Liquidating -> redeem (burn tokens, receive NAV share)
Any time after launch: collect_trading_fees, collect_surplus, claim_lp_fees -> treasury
After graduation, price < backing: defend_floor -> DAMM v2 swap (treasury pays) -> burn
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

Program `GBHTxatkmbAX5U7G65yXzDVAZjjjyW9btGZ1DNUHtcfh`. `scripts/demo.ts` runs two real raises
(happy path with a defended floor, and a rejected tranche that ends in redemptions); every
transaction is linked in [`docs/DEMO-devnet.md`](docs/DEMO-devnet.md).

## Web app

`app/` is a Vite + React front end that reuses the same client as the scripts (`scripts/lib/owncurve.ts`).
It lists every raise, draws the treasury as a vault split into tranches, shows the guarantees that
`bind_pool` checked on-chain, and lets anyone buy, object, settle and redeem. Connect a browser wallet
(Phantom, Solflare, Backpack…) or click **Use a test wallet** to try it on devnet without installing anything.

```
npm run app            # http://localhost:5173 (devnet; set VITE_RPC_URL in app/.env.local)
npm run e2e            # Chromium drives the whole lifecycle against LiteSVM with the real programs
```

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
CLUSTER=local npx tsx --test tests/owncurve.test.ts   # 23 integration tests, real DBC + DAMM v2 binaries
npx tsx --test tests/cli.test.ts                      # the agent CLI end to end over JSON-RPC
npm run e2e                                           # Chromium drives the app, incl. floor defense
CLUSTER=local npx tsx scripts/f1.ts --migrate        # end-to-end flow in LiteSVM
npx tsx scripts/f1.ts --migrate                      # same flow on devnet
```

Local tests need `local/dynamic_bonding_curve.so` (built from DBC source at f552f20) and
`local/damm_v2.so` (DBC repo test fixture); `owncurve.sh` prepares both.

## Known limitations (MVP)

- Tokens sitting in the DBC/DAMM v2 pool count as circulating supply, so redemption pays them
  out only when someone buys them from the pool and redeems (an arbitrage floor, by design).
- Votes are locked tokens with no snapshot; flash-borrowed votes are possible but cost a round trip.

## License

MIT
