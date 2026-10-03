# OwnCurve

Ownership coins on Meteora's Dynamic Bonding Curve (DBC).

A raise is a normal DBC launch whose config names OwnCurve's treasury PDA as
`fee_claimer` and `leftover_receiver`. At graduation the DBC migration fee (up to
99% of the raise) is pulled into an on-chain treasury instead of a wallet. The team
is paid in milestone tranches; holders can lock tokens to reject a tranche, and a
rejection that reaches quorum turns the treasury into a pro-rata redemption pool.
After graduation the treasury also owns the DAMM v2 LP position, so it keeps earning
trading fees forever.

Built for the Colosseum Crypto World's Fair — "Best use of Meteora's DBC" sidetrack.

## Lifecycle

```
Pending --bind_pool--> Bonding --harvest (CPI)--> Funded
Funded --propose_release + reject votes--> finalize
    quorum not reached -> tranche to team -> Funded (next milestone) / Completed (last)
    quorum reached     -> Liquidating -> redeem (burn tokens, receive NAV share)
Any time after launch: collect_trading_fees, collect_surplus, claim_lp_fees -> treasury
```

## Instructions

| Instruction | Caller | What it does |
| --- | --- | --- |
| `init_raise` | team | Milestone tranches (sum 10000 bps), min treasury %, challenge window, reject quorum |
| `bind_pool` | anyone | Validates the live DBC config + pool before anyone buys (see guarantees) |
| `harvest` | anyone | CPI `withdraw_migration_fee` signed by the treasury PDA |
| `collect_trading_fees` | anyone | CPI `claim_trading_fee`: partner share of curve fees → treasury |
| `collect_surplus` | anyone | CPI `partner_withdraw_surplus` → treasury |
| `claim_lp_fees` | anyone | CPI DAMM v2 `claim_position_fee` for the treasury-owned position |
| `propose_release` | team | Opens a challenge window for the next milestone |
| `reject` | holder | Locks base tokens in escrow as a reject vote |
| `finalize` | anyone | Pays the tranche, or switches to liquidation if quorum was met |
| `withdraw_vote` | holder | Returns locked tokens after finalize |
| `redeem` | holder | In liquidation: burn tokens, receive a pro-rata share of the treasury |

## On-chain guarantees (enforced by `bind_pool` / `init_raise`)

- `fee_claimer` and `leftover_receiver` of the DBC config are the treasury PDA: only this program can move the raise.
- The creator gets 0% of the migration fee and its DAMM v2 LP is 100% permanently locked (no liquidity rug).
- The creator never holds the mint authority (no infinite mint).
- The migration fee routed to the treasury is at least the raise's `min_treasury_pct` (≥ 50%).
- Holders always get a challenge window of ≥ 60 s, and blocking a tranche never needs more than 30% of supply.
- Fees, surplus and LP fees can only be sent to treasury-owned token accounts.

## Verified against DBC source (program 0.2.1, commit f552f20)

- `MAX_MIGRATION_FEE_PERCENTAGE = 99`; `create_config` takes `fee_claimer` as an unchecked account, so it can be a PDA.
- `withdraw_migration_fee`, `claim_trading_fee` and `partner_withdraw_surplus` require `fee_claimer` as signer.
- On DAMM v2 migration the partner position is minted to `config.fee_claimer` (the treasury).

## Devnet (F1)

Program `GBHTxatkmbAX5U7G65yXzDVAZjjjyW9btGZ1DNUHtcfh`: a full raise was created, bought to
graduation, harvested (0.4 SOL = 80% of 0.5 SOL into the treasury PDA) and migrated to DAMM v2.

## Web app

`app/` is a Vite + React front end that reuses the same client as the scripts (`scripts/lib/owncurve.ts`).
It lists every raise, draws the treasury as a vault split into tranches, shows the guarantees that
`bind_pool` checked on-chain, and lets anyone buy, object, settle and redeem. Connect a browser wallet
(Phantom, Solflare, Backpack…) or click **Use a test wallet** to try it on devnet without installing anything.

```
npm run app            # http://localhost:5173 (devnet; set VITE_RPC_URL in app/.env.local)
npm run e2e            # Chromium drives the whole lifecycle against LiteSVM with the real programs
```

## Build and test

```
anchor build --skip-lint --tools-version v1.52 --arch v0
npm ci
CLUSTER=local npx tsx --test tests/owncurve.test.ts   # 17 integration tests, real DBC + DAMM v2 binaries
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
