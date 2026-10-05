# OwnCurve · submission kit

Links (fill in automatically by `owncurve.sh`):

- Repo: https://github.com/Zyxel89/owncurve
- Live app (devnet): https://zyxel89.github.io/owncurve/
- Demo raise A (tranches + floor): https://zyxel89.github.io/owncurve/#/raise/7sDbgBXGy6o5AWs6NpCUG8EfuRCTBqzKG8SNZ8Prb7Ra
- Demo raise B (rejected → redemptions): https://zyxel89.github.io/owncurve/#/raise/ERrfcHfstYDDgamvvRYS3XDkJ2LmZk8Dei6sMhSQV9tW
- Demo raise C (raised in a stablecoin, tUSD): https://zyxel89.github.io/owncurve/#/raise/FLtDebR8xRPrLcmGTDwA1XSfn3JbFw9ts5APNrDEQW3m
- Demo raise D (raised in a tokenized stock, tNVDAx, floor defended): https://zyxel89.github.io/owncurve/#/raise/FDtBpfVYe1NJKNWWiuieJueFPKfmDY6XJhJyRxjc1aQe
- Demo raise E (taken over through the on-chain Bedrock clause): https://zyxel89.github.io/owncurve/#/raise/8toF88iSKFRstDfZzsRNkHz2GBet84K5ztgBEkXyFXNN
- Demo raise F (silent team → treasury back to holders): https://zyxel89.github.io/owncurve/#/raise/DVW29fmVR36A65xViVbuJNTzMMAvJro8vm4tpvX7MimF
- Rug check any Meteora launch: https://zyxel89.github.io/owncurve/#/scan
- Mainnet study: https://github.com/Zyxel89/owncurve/blob/main/docs/MAINNET-STUDY.md
- Program (devnet): https://explorer.solana.com/address/GBHTxatkmbAX5U7G65yXzDVAZjjjyW9btGZ1DNUHtcfh?cluster=devnet
- Video: (YouTube/Loom link)

## One-liner

Ownership coins on Meteora: the bonding curve's raise goes into an on-chain treasury that pays
the team one evidence-backed milestone at a time, lets holders stop a payment and take their
share back, and buys the token back below its backing. Raise in SOL, USDC or tokenized stocks;
govern it from the web, a CLI, an Agent Skill or an MCP server.

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
Raises can be quoted in SOL, any SPL token (USDC) or any Token-2022 token (xStocks). An MCP
server and an Agent Skill let AI agents launch, audit and govern raises, simulating every write
unless confirmed. Meteora Bedrock's takeover clause runs as code: the program keeps its own TWAP from
DAMM v2 and the only way to take a raise over is a tender offer that pays every holder TWAP +30%.
If the team goes silent, anyone can return the treasury to holders. A rug check grades any mainnet
DBC launch, and a mainnet study of every DBC config and launch measures the gap OwnCurve closes.

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

- Its own Anchor program (17 instructions) doing CPI into DBC and DAMM v2, not an SDK wrapper.
- 29 integration tests against the real DBC and DAMM v2 binaries (LiteSVM), including full
  lifecycles in an SPL stablecoin and a Token-2022 tokenized stock; CLI, MCP and mainnet-study tests;
  a browser E2E test that drives the whole lifecycle in Chromium.
- Six raises on devnet (tranches + floor, rejection, stablecoin, tokenized stock, Bedrock takeover, ghost team) with every transaction linked: `docs/DEMO-devnet.md`.
- security.txt embedded in the program, IDL on-chain, `scripts/verify.sh` matches the devnet binary to the source.

## Judging criteria → where to look

| Criterion | Evidence |
| --- | --- |
| Depth of Meteora integration | Treasury PDA is DBC `fee_claimer`; CPI `withdraw_migration_fee`, `claim_trading_fee`, `partner_withdraw_surplus`; DBC→DAMM v2 migration; CPI DAMM v2 `claim_position_fee` and `swap` |
| Technical execution | Anchor program + 25 integration tests on real Meteora binaries, E2E, CLI/MCP tests, verify script |
| Originality and taste | Milestone escrow with on-chain evidence, holder objections → redemptions, self-defending price floor, Meteora Bedrock's takeover clause as code, ghost-team switch |
| Impact potential | Any DBC launchpad can add "ownership coin" mode; works for stablecoin and RWA (xStock) raises; agents can be holder guardians |
| Traction | Live app, six devnet raises, rug check that works on any mainnet DBC launch, mainnet study of every DBC launch |

## Video script (~2 min; check the form for its limits)

1. **0:00–0:15 Problem.** "Token raises go to a wallet on day one. If the team stops shipping, holders hold nothing."
2. **0:15–0:35 Idea.** Show the raise page: the vault bar. "OwnCurve sends Meteora's bonding-curve raise to a treasury that pays the team one milestone at a time."
3. **0:35–1:05 Live.** Launch a raise with the test wallet, buy, "Move the raise into the treasury". Point at the guarantees checked on-chain.
4. **1:05–1:25 Evidence + objection.** Request a tranche with a link; switch to a holder, see the link and SHA-256, object; settle → liquidation → redeem.
5. **1:25–1:45 Floor.** Demo raise A: price vs backing panel, "Buy back below backing", tokens burned, backing up.
6. **1:45–2:00 Close.** "Agent Skill: your AI can audit milestones and object for you. Built on DBC + DAMM v2, open source, live on devnet."
