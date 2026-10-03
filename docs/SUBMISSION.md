# OwnCurve · submission kit

Links (fill in automatically by `owncurve.sh`):

- Repo: https://github.com/Zyxel89/owncurve
- Live app (devnet): https://zyxel89.github.io/owncurve/
- Demo raise A (tranches + floor): https://zyxel89.github.io/owncurve/#/raise/__RAISE_A__
- Demo raise B (rejected → redemptions): https://zyxel89.github.io/owncurve/#/raise/__RAISE_B__
- Program (devnet): https://explorer.solana.com/address/GBHTxatkmbAX5U7G65yXzDVAZjjjyW9btGZ1DNUHtcfh?cluster=devnet
- Video: (YouTube/Loom link)

## One-liner

Ownership coins on Meteora: the bonding curve's raise goes into an on-chain treasury that pays
the team one evidence-backed milestone at a time, lets holders stop a payment and take their
share back, and buys the token back below its backing.

## Description (≈150 words)

Most launchpad raises go straight to a wallet. OwnCurve makes Meteora's Dynamic Bonding Curve
fund an on-chain treasury instead: the DBC config names OwnCurve's PDA as `fee_claimer`, so at
graduation up to 99% of the raise is pulled into the treasury by CPI. The team is paid in
milestone tranches; each request stores a link to the delivered work and its SHA-256 on-chain,
and holders get a challenge window to object. If objections reach quorum, the treasury becomes
a pro-rata redemption pool. After migration to DAMM v2 the treasury owns the LP position and
earns its fees, and a floor reserve buys the token back whenever it trades below its backing
— the program refuses to pay more than backing and burns what it buys. `bind_pool` verifies the
whole DBC config before anyone buys (no creator LP, no mint authority, fee to treasury).
An Agent Skill lets AI agents launch, audit and govern raises.

## How it uses Meteora

| Meteora piece | Used for |
| --- | --- |
| DBC `create_config` / pool | The launch; fee_claimer + leftover_receiver = treasury PDA, migration fee up to 99% |
| DBC `withdraw_migration_fee` (CPI, PDA signer) | Funds the treasury at graduation |
| DBC `claim_trading_fee`, `partner_withdraw_surplus` (CPI) | Curve fees and surplus → treasury |
| DBC → DAMM v2 migration | Partner LP position minted to the treasury |
| DAMM v2 `claim_position_fee` (CPI) | LP fees → treasury, forever |
| DAMM v2 `swap` (CPI, treasury pays) | Price-floor buybacks, capped at backing, then burned |

## Proof

- 23 integration tests against the real DBC and DAMM v2 binaries (LiteSVM), a CLI test, and a
  browser E2E test that drives the whole lifecycle in Chromium.
- Full lifecycle on devnet: `docs/DEMO-devnet.md`.

## Video script (~2 min; check the form for its limits)

1. **0:00–0:15 Problem.** "Token raises go to a wallet on day one. If the team stops shipping, holders hold nothing."
2. **0:15–0:35 Idea.** Show the raise page: the vault bar. "OwnCurve sends Meteora's bonding-curve raise to a treasury that pays the team one milestone at a time."
3. **0:35–1:05 Live.** Launch a raise with the test wallet, buy, "Move the raise into the treasury". Point at the guarantees checked on-chain.
4. **1:05–1:25 Evidence + objection.** Request a tranche with a link; switch to a holder, see the link and SHA-256, object; settle → liquidation → redeem.
5. **1:25–1:45 Floor.** Demo raise A: price vs backing panel, "Buy back below backing", tokens burned, backing up.
6. **1:45–2:00 Close.** "Agent Skill: your AI can audit milestones and object for you. Built on DBC + DAMM v2, open source, live on devnet."
