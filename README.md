# OwnCurve

Ownership coins on Meteora's Dynamic Bonding Curve (DBC).

A raise is a normal DBC launch whose config names OwnCurve's treasury PDA as
`fee_claimer` and `leftover_receiver`. At graduation the DBC migration fee (up to
99% of the raise) is pulled into an on-chain treasury instead of a wallet. The team
is paid in milestone tranches; holders can lock tokens to reject a tranche, and a
rejection that reaches quorum turns the treasury into a pro-rata redemption pool.

Built for the Colosseum Crypto World's Fair — "Best use of Meteora's DBC" sidetrack.

## Lifecycle

```
Pending --bind_pool--> Bonding --harvest (CPI)--> Funded
Funded --propose_release + reject votes--> finalize
    quorum not reached -> tranche to team -> Funded (next milestone) / Completed (last)
    quorum reached     -> Liquidating -> redeem (burn tokens, receive NAV share)
```

## Instructions

| Instruction | Caller | What it does |
| --- | --- | --- |
| `init_raise` | team | Milestone tranches (sum 10000 bps), min treasury %, challenge window, reject quorum |
| `bind_pool` | anyone | Validates the live DBC config + pool: fee_claimer and leftover_receiver = treasury PDA, creator migration fee = 0, migration fee >= min, pool creator = team |
| `harvest` | anyone | CPI `withdraw_migration_fee` signed by the treasury PDA |
| `propose_release` | team | Opens a challenge window for the next milestone |
| `reject` | holder | Locks base tokens in escrow as a reject vote |
| `finalize` | anyone | Pays the tranche, or switches to liquidation if quorum was met |
| `withdraw_vote` | holder | Returns locked tokens after finalize |
| `redeem` | holder | In liquidation: burn tokens, receive a pro-rata share of the treasury |

## Verified against DBC source (program 0.2.1, commit f552f20)

- `MAX_MIGRATION_FEE_PERCENTAGE = 99` (`constants.rs`).
- `create_config` takes `fee_claimer` as an unchecked account, so it can be a PDA.
- `withdraw_migration_fee` requires `sender == config.fee_claimer` and a completed curve; no CPI restriction.
- Partner trading fees and partner surplus also require `fee_claimer` as signer.
- On transfer-hook configs, `PartnerUpdateAndMintAuthority` gives the mint authority to `config.fee_claimer`.

## Build

```
cargo check
cargo test
```

Needs Rust 1.93+. DBC is pulled as a git dependency pinned to commit `f552f20` with the `cpi` feature.
For deploys: Solana CLI 3.1 and Anchor 1.0 (`anchor build`). The program ID in `declare_id!` is a placeholder.

## Known gaps (MVP)

- [ ] Integration tests on localnet with the DBC `.so` loaded.
- [ ] `harvest` only pulls the migration fee; partner trading fees, partner surplus and leftover still need their own CPIs.
- [ ] The treasury quote token account must exist before `harvest` (client creates the ATA).
- [ ] Tokens inside the DAMM v2 pool count toward supply, so redemption slightly underpays.
- [ ] `init_raise` must be sent in the same transaction that creates the DBC config keypair, otherwise someone can occupy the raise PDA for that config first.
- [ ] Optional transfer-hook mode (treasury holds the mint authority).

## License

MIT
