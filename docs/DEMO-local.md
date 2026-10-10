# OwnCurve · local demo

Program: [`GBHTxatkmbAX5U7G65yXzDVAZjjjyW9btGZ1DNUHtcfh`](GBHTxatkmbAX5U7G65yXzDVAZjjjyW9btGZ1DNUHtcfh) · every transaction below is real and links to the explorer.

## Raise A · tranches with evidence + price floor (SOL)

Treasury [`BKJRr7ybg2ubHY2ab4rv3hR4s6GqNHLcJpi8vhq2fgnZ`](BKJRr7ybg2ubHY2ab4rv3hR4s6GqNHLcJpi8vhq2fgnZ) · funded 0.4000 SOL · paid to the team in 3 evidence-backed tranches 0.3200 SOL (all of the payable 0.3200) · fees collected 0.0042 SOL · floor defense 0.0396 SOL · the treasury still holds 0.0446 SOL of backing for holders · final state **completed**.

| Step | Result | Transaction |
| --- | --- | --- |
| A1 init_raise + DBC create_config |  | [view](local:2c9764e62c2624ca) |
| A2 DBC create_pool + bind_pool (on-chain checks) |  | [view](local:654037eea27afdcd) |
| A3 buy until the curve graduates | reserve 0.5000 SOL | [view](local:1af17e58bc447850) |
| A4 harvest | treasury 0.4000 SOL | [view](local:32a9cf6be6e2c8f2) |
| A5 collect curve trading fees (CPI) | +0.0040 SOL | [view](local:d8b2d3ff3ddad22c) |
| A6 migrate to DAMM v2 |  | [view](local:e0d373942d4815ac) |
| A7 swap on DAMM v2 |  | [view](local:c320523d73033f77) |
| A8 claim LP fees of the treasury position (CPI) | total fees 0.0042 SOL | [view](local:d29bba0e1d660e58) |
| A8b panic sell on DAMM v2 | price 0.0000203 vs backing 0.000404 SOL per 1M tokens | [view](local:26938eb02bbc45fc) |
| A8c defend_floor | bought back 0.0396 SOL, burned 473,177,901 tokens, backing +71% | [view](local:5f121f07220006f6) |
| A9.1 propose tranche 1 with evidence |  | [view](local:40e7a739a7948d6d) |
| A9.1 settle tranche 1 | released 0.0960 / 0.3200 SOL | [view](local:0766e924f01d26b0) |
| A9.2 propose tranche 2 with evidence |  | [view](local:8fa9ce9f8c699f5a) |
| A9.2 settle tranche 2 | released 0.1920 / 0.3200 SOL | [view](local:a3b9f0b0df5eae11) |
| A9.3 propose tranche 3 with evidence |  | [view](local:e4c23d80d8e55dd7) |
| A9.3 settle tranche 3 | released 0.3200 / 0.3200 SOL | [view](local:9398a343d983aa3c) |

## Raise B · holders stop a tranche → liquidation → redemption (SOL)

Treasury [`7zuyV8v4CVoZDe3Yvwg643NW5FFtaFzsC4TZFAV8Riu4`](7zuyV8v4CVoZDe3Yvwg643NW5FFtaFzsC4TZFAV8Riu4) · funded 0.2400 SOL · final state **liquidating**: the team got nothing and holders redeem against the treasury.

| Step | Result | Transaction |
| --- | --- | --- |
| B1 init_raise + DBC create_config |  | [view](local:68d996124d72a735) |
| B2 DBC create_pool + bind_pool (on-chain checks) |  | [view](local:ce81ea6419bc7dac) |
| B3 buy until the curve graduates |  | [view](local:8302d50ddb716500) |
| B4 harvest | treasury 0.2400 SOL | [view](local:7504e9506930c55f) |
| B6 holder receives 15% of supply |  | [view](local:e313ee7df1807150) |
| B7 team proposes tranche 1 |  | [view](local:dff358b40ffa1f5c) |
| B8 holder objects (locks tokens) | locked 150000000000000 tokens (base units) | [view](local:5d946a1d58988013) |
| B10 settle → liquidation | state "liquidating" | [view](local:b84cfca03dfdfb3e) |
| B11 holder unlocks voted tokens |  | [view](local:5c0e5da2bc3a5377) |
| B12 holder redeems tokens for SOL | received 0.0360 SOL (wSOL) for the tokens | [view](local:453bd72e55d1836f) |

## Raise C · raised in a stablecoin (tUSD, SPL token like USDC)

Currency [`F3PFEkHmAzyCt19fihMjg1YRZCg6ucGdJxEY3Ask83W5`](F3PFEkHmAzyCt19fihMjg1YRZCg6ucGdJxEY3Ask83W5) (devnet test token) · treasury [`EkAtc2Jm3G7ncfeHTa8JS8BNHePuYDvC4wRPAWvMx8WM`](EkAtc2Jm3G7ncfeHTa8JS8BNHePuYDvC4wRPAWvMx8WM) · funded 80.00 tUSD · tranche 1 paid 19.20 tUSD.

| Step | Result | Transaction |
| --- | --- | --- |
| C1 init_raise + DBC create_config (raised in tUSD) |  | [view](local:e145792ecc22497c) |
| C2 DBC create_pool + bind_pool (on-chain checks) |  | [view](local:ddaf812708cc7016) |
| C3 buy until the curve graduates |  | [view](local:43acfcce32c2ce77) |
| C4 harvest | treasury 80.00 tUSD | [view](local:a6b38a394ef3c55d) |
| C5 migrate to DAMM v2 |  | [view](local:17ad0ff7c366abb7) |
| C6 propose tranche 1 with evidence |  | [view](local:75b5aaa47c25fc04) |
| C8 settle tranche 1 | released 19.20 tUSD | [view](local:52f159b08785d40e) |

## Raise D · raised in a tokenized stock (tNVDAx, Token-2022 like xStocks)

Currency [`CJxpbdZ6XrGv4umpkfAaJV183B4odUq22pqrrF83cEDp`](CJxpbdZ6XrGv4umpkfAaJV183B4odUq22pqrrF83cEDp) (devnet test token) · treasury [`E4itrTFKaWJqXvBe6WwQcyujpWbzDJZzu62VrskJSUrP`](E4itrTFKaWJqXvBe6WwQcyujpWbzDJZzu62VrskJSUrP) · funded 0.8000 tNVDAx · floor defense 0.0789 tNVDAx.

| Step | Result | Transaction |
| --- | --- | --- |
| D1 init_raise + DBC create_config (raised in tNVDAx) |  | [view](local:f913a69421fb470c) |
| D2 DBC create_pool + bind_pool (on-chain checks) |  | [view](local:d920c52d8af2db56) |
| D3 buy until the curve graduates |  | [view](local:0d836163095b2b61) |
| D4 harvest | treasury 0.8000 tNVDAx | [view](local:062936019e7b9eb4) |
| D5 migrate to DAMM v2 |  | [view](local:9c4ee7fd4ef25139) |
| D6 panic sell on DAMM v2 |  | [view](local:fd378bd37792adfa) |
| D7 defend_floor | bought back 0.0789 tNVDAx, backing +73% | [view](local:e63b4479ad1aacf0) |

## Raise E · Meteora Bedrock's takeover clause, enforced on-chain

Treasury [`2QL7E4mVUvJkebWnWgryj1UCKKNiPfGMJbvzyDDJXAPA`](2QL7E4mVUvJkebWnWgryj1UCKKNiPfGMJbvzyDDJXAPA) · the program built its own TWAP from DAMM v2 price observations; a takeover had to top the treasury up so every holder redeems at TWAP +30%. TWAP 0.000625 → offer 0.000812 SOL per 1M tokens (+30%), deposit 0.6125 SOL · final state **liquidating**, new team Ca1fbC….

| Step | Result | Transaction |
| --- | --- | --- |
| E1 init_raise + init_guard + DBC create_config |  | [view](local:3e75b6b4037de43c) |
| E2 DBC create_pool + bind_pool (on-chain checks) |  | [view](local:15fffe92481890a2) |
| E3 buy until the curve graduates |  | [view](local:be5f96654d5c07e1) |
| E4 harvest + arm_guard (inactivity clock starts) | treasury 0.2000 SOL | [view](local:699575e289a9dfce) |
| E5 migrate to DAMM v2 |  | [view](local:54c816916c29b914) |
| E6 holder receives 5% of supply |  | [view](local:d0623ecb2720df87) |
| E7.1 observe: record the DAMM v2 price for the TWAP |  | [view](local:130659a38cfa87a6) |
| E7.2 observe: record the DAMM v2 price for the TWAP |  | [view](local:520f6e8379524fae) |
| E7.3 observe: record the DAMM v2 price for the TWAP |  | [view](local:8c71dd41868ccdaa) |
| E7.4 observe: record the DAMM v2 price for the TWAP |  | [view](local:f98f13f19189ef8e) |
| E7.5 observe: record the DAMM v2 price for the TWAP |  | [view](local:275142b1227fdd3f) |
| E8 tender_offer: takeover paying every holder TWAP +30% | TWAP 0.000625 → offer 0.000812 SOL per 1M tokens (+30%), deposit 0.6125 SOL | [view](local:9961a2ef478f3c01) |
| E9 holder redime a price de offer | received 0.0406 SOL: 30% above the TWAP | [view](local:5a1676da61f7df3d) |
| E10 acquirer redeems its own tokens |  | [view](local:ecbc778a29c11595) |

## Raise F · the team went silent, the treasury went back to holders

Treasury [`ERM3AavC6qDYbpYorwShsBNFBPhuHCebuLHtyp4WLNqG`](ERM3AavC6qDYbpYorwShsBNFBPhuHCebuLHtyp4WLNqG) · funded 0.0800 SOL · no tranche request within the guard's window (60 s on devnet), so anyone could call `declare_abandoned` · final state **liquidating**.

| Step | Result | Transaction |
| --- | --- | --- |
| F1 init_raise + init_guard (60 s inactivity) + DBC create_config |  | [view](local:fa184f3e2e9b1233) |
| F2 DBC create_pool + bind_pool (on-chain checks) |  | [view](local:4ceecfdcd8e776c2) |
| F3 buy until the curve graduates |  | [view](local:8069938df92b3d8e) |
| F4 harvest + arm_guard (inactivity clock starts) | treasury 0.0800 SOL | [view](local:bb0e3d205dd8fd33) |
| F6 declare_abandoned | state "liquidating" | [view](local:93ce7ef0cc569320) |

## Raise G · operating budget, kept alive by the keeper

Treasury [`Gs5cxSYfc1MzM8FdCL82BiiexdPeCwzPVaKJDKNNAPNW`](Gs5cxSYfc1MzM8FdCL82BiiexdPeCwzPVaKJDKNNAPNW) · the team draws a bounded budget every 10 min as an advance on its next tranche; tranche 1 was requested and the public keeper settles it, records the DAMM v2 price for the TWAP every run and would return the treasury if the team went silent for 7 days.

| Step | Result | Transaction |
| --- | --- | --- |
| G1 init_raise + init_guard + DBC create_config + presupuesto |  | [view](local:bf2889858316b2a1) |
| G2 DBC create_pool + bind_pool (on-chain checks) |  | [view](local:a2e3a5fc52913a59) |
| G3 buy until the curve graduates |  | [view](local:30f5112f194ab193) |
| G4 harvest + arm_guard (inactivity clock starts) | treasury 0.1600 SOL | [view](local:0c909e1e828d485f) |
| G5 migrate to DAMM v2 |  | [view](local:ebba5a99f37ee803) |
| G6 draw_budget | budget 0.0050 SOL, advanced on tranche 1 | [view](local:f3aabdd0b6e9bdac) |
| G7 propose tranche 1 with evidence (lo liquida el keeper) |  | [view](local:bcde88a35d2000da) |
