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
- Demo raise G (operating budget, kept alive by the keeper): https://zyxel89.github.io/owncurve/#/raise/68WZeVdNN4vNujsArou2es2P59V6VtuYPKipAmnSu4Y
- Keeper activity (runs every 10 min, no humans): https://zyxel89.github.io/owncurve/#/keeper
- Rug check any Meteora launch: https://zyxel89.github.io/owncurve/#/scan
- Mainnet study: https://github.com/Zyxel89/owncurve/blob/main/docs/MAINNET-STUDY.md
- Program (devnet): https://explorer.solana.com/address/GBHTxatkmbAX5U7G65yXzDVAZjjjyW9btGZ1DNUHtcfh?cluster=devnet
- Video: (YouTube/Loom link)

## One-liner

Ownership coins on Meteora: the bonding curve's raise goes into an on-chain treasury that pays
the team one evidence-backed milestone at a time, lets holders stop a payment and take their
share back, and buys the token back below its backing. Raise in SOL, USDC or tokenized stocks;
govern it from the web, a CLI, an Agent Skill or an MCP server.

## The numbers (mainnet, read on-chain by `scripts/study.ts`)

- 1,738,512 Meteora DBC launches over 534,981 configs.
- 63.6% of launches let someone withdraw the graduated liquidity. OwnCurve: 0%.
- 10.1% meet four basic holder guarantees. OwnCurve: 100%, checked on-chain before the first buy.

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
If the team goes silent, anyone can return the treasury to holders. Teams can draw a bounded
operating budget that is only ever an advance on their next tranche. A public keeper runs every
protection every 10 minutes, so nothing depends on someone clicking a button. A rug check grades any mainnet
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

- Its own Anchor program (19 instructions) doing CPI into DBC and DAMM v2, not an SDK wrapper.
- 31 integration tests against the real DBC and DAMM v2 binaries (LiteSVM), including full
  lifecycles in an SPL stablecoin and a Token-2022 tokenized stock; CLI, MCP and mainnet-study tests;
  a browser E2E test that drives the whole lifecycle in Chromium.
- Seven raises on devnet (tranches + floor, rejection, stablecoin, tokenized stock, Bedrock takeover, ghost team, budget + keeper) and a keeper acting on devnet every 10 minutes with every transaction linked: `docs/DEMO-devnet.md`.
- security.txt embedded in the program, IDL on-chain, `scripts/verify.sh` matches the devnet binary to the source.

## Judging criteria → where to look

| Criterion | Evidence |
| --- | --- |
| Depth of Meteora integration | Treasury PDA is DBC `fee_claimer`; CPI `withdraw_migration_fee`, `claim_trading_fee`, `partner_withdraw_surplus`; DBC→DAMM v2 migration; CPI DAMM v2 `claim_position_fee` and `swap` |
| Technical execution | Anchor program + 25 integration tests on real Meteora binaries, E2E, CLI/MCP tests, verify script |
| Originality and taste | Milestone escrow with on-chain evidence, holder objections → redemptions, self-defending price floor, Meteora Bedrock's takeover clause as code, ghost-team switch |
| Impact potential | Any DBC launchpad can add "ownership coin" mode; works for stablecoin and RWA (xStock) raises; agents can be holder guardians |
| Traction | Live app, seven devnet raises, an autonomous keeper transacting every 10 min, rug check that works on any mainnet DBC launch, mainnet study of every DBC launch |

## Pitch video (max 3 min) — the "why"

1. **0:00–0:20 · Who.** "I'm [name], a Rust developer from [country]. I built OwnCurve for this hackathon."
2. **0:20–0:55 · Problem, with data.** Show the home page stats. "We read all 1.7 million Meteora DBC launches on mainnet. In 63.6% of them someone can pull the liquidity after graduation. Only one in ten meets four basic holder guarantees. Meteora launched Bedrock this year to protect holders with lawyers. We think code should do it."
3. **0:55–1:40 · Solution.** Vault bar of the "floor defended" raise. "OwnCurve turns a DBC launch into an ownership coin. The raise sits in an on-chain treasury. The team is paid one milestone at a time, each with a public link and a hash on-chain. Holders can stop a payment and take their share back. If the team goes silent, the treasury goes back to holders. And Bedrock's takeover clause runs as code: nobody can take the project over without paying every holder the TWAP plus 30%."
4. **1:40–2:20 · Proof.** Rug check a real mainnet token live (grade D or F), then an OwnCurve raise (A+). "Six raises live on devnet, in SOL, a stablecoin and a tokenized stock."
5. **2:20–2:50 · Why it wins / next.** "Any launchpad on Meteora can turn this on for its creators. Next: audit, mainnet, and an integration with Bedrock launchpads."

## Technical demo (2–3 min) — the "how"

1. **0:00–0:25 · Architecture.** README diagram: Anchor program, treasury PDA as DBC `fee_claimer`, CPIs into DBC (`withdraw_migration_fee`, `claim_trading_fee`, `partner_withdraw_surplus`) and DAMM v2 (`claim_position_fee`, `swap`).
2. **0:25–1:10 · Live in the app.** Launch a raise with the test wallet (show the guard fields), buy to graduation, "Move the raise into the treasury" (harvest + arm_guard in one tx), request a tranche with evidence, object from a second wallet, settle → redemptions.
3. **1:10–1:40 · Price floor + Bedrock.** Raise A panel: buyback below backing and burn. Raise E: `observe` builds the TWAP from DAMM v2 (`sqrt_price` read from the pool, owner and mints checked), `tender_offer` deposits until each token redeems at TWAP × 1.3.
4. **1:40–2:10 · Agents.** Claude Desktop with the OwnCurve MCP server: "check the pending tranche of raise X" → it reads the evidence, explains, simulates `object`, and only sends with confirm.
5. **2:10–2:40 · Quality.** `npm test` (29 integration tests on the real Meteora binaries), the CLI/MCP/scan/study tests, the Chromium E2E, `scripts/verify.sh` matching the devnet binary, security.txt.
