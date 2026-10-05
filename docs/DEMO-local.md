# OwnCurve · local demo

Program: [`GBHTxatkmbAX5U7G65yXzDVAZjjjyW9btGZ1DNUHtcfh`](GBHTxatkmbAX5U7G65yXzDVAZjjjyW9btGZ1DNUHtcfh) · every transaction below is real and links to the explorer.

## Raise A · tranches with evidence + price floor (SOL)

Treasury [`22tYxzKpr7SYSb9pNZSM9uC6PYhtVMFxkAxUB7BYkzJ7`](22tYxzKpr7SYSb9pNZSM9uC6PYhtVMFxkAxUB7BYkzJ7) · funded 0.4000 SOL · paid to the team in 3 evidence-backed tranches 0.3200 SOL (all of the payable 0.3200) · fees collected 0.0042 SOL · floor defense 0.0396 SOL · the treasury still holds 0.0446 SOL of backing for holders · final state **completed**.

| Step | Result | Transaction |
| --- | --- | --- |
| A1 init_raise + DBC create_config |  | [view](local:cd30656762fa6321) |
| A2 DBC create_pool + bind_pool (on-chain checks) |  | [view](local:02d3cc5b6e2decae) |
| A3 buy until the curve graduates | reserve 0.5000 SOL | [view](local:bbe4c169c97bd8d6) |
| A4 harvest | treasury 0.4000 SOL | [view](local:08216fb3213e35ec) |
| A5 collect curve trading fees (CPI) | +0.0040 SOL | [view](local:eb9ee3d9101e39be) |
| A6 migrate to DAMM v2 |  | [view](local:b7a6e0467c984cb7) |
| A7 swap on DAMM v2 |  | [view](local:405bd7409f16ef97) |
| A8 claim LP fees of the treasury position (CPI) | total fees 0.0042 SOL | [view](local:61ec793e5c8e71e3) |
| A8b panic sell on DAMM v2 | price 0.0000203 vs backing 0.000404 SOL per 1M tokens | [view](local:d491d14589f9294c) |
| A8c defend_floor | bought back 0.0396 SOL, burned 473,177,901 tokens, backing +71% | [view](local:4a1b0335a23c3eb9) |
| A9.1 propose tranche 1 with evidence |  | [view](local:845677bf535b59f1) |
| A9.1 settle tranche 1 | released 0.0960 / 0.3200 SOL | [view](local:c85f410dfd36a86d) |
| A9.2 propose tranche 2 with evidence |  | [view](local:0e308aed0edfef65) |
| A9.2 settle tranche 2 | released 0.1920 / 0.3200 SOL | [view](local:b52676e3cc9def98) |
| A9.3 propose tranche 3 with evidence |  | [view](local:08efa04ee14cd307) |
| A9.3 settle tranche 3 | released 0.3200 / 0.3200 SOL | [view](local:4f6401b79734e3c0) |

## Raise B · holders stop a tranche → liquidation → redemption (SOL)

Treasury [`GDoLZPDaPn314nUs6pJsoVaoNBmGBrRtUcetUSjLRzFJ`](GDoLZPDaPn314nUs6pJsoVaoNBmGBrRtUcetUSjLRzFJ) · funded 0.2400 SOL · final state **liquidating**: the team got nothing and holders redeem against the treasury.

| Step | Result | Transaction |
| --- | --- | --- |
| B1 init_raise + DBC create_config |  | [view](local:68661aac1e7edc77) |
| B2 DBC create_pool + bind_pool (on-chain checks) |  | [view](local:7bbe6b3d7e174320) |
| B3 buy until the curve graduates |  | [view](local:d4649d97c29412ab) |
| B4 harvest | treasury 0.2400 SOL | [view](local:e2966b33ba1138ef) |
| B6 holder receives 15% of supply |  | [view](local:6322d41915c08032) |
| B7 team proposes tranche 1 |  | [view](local:417b5c73ac331139) |
| B8 holder objects (locks tokens) | locked 150000000000000 tokens (base units) | [view](local:a03c36fa92288c69) |
| B10 settle → liquidation | state "liquidating" | [view](local:cdc846d2ae69a61e) |
| B11 holder unlocks voted tokens |  | [view](local:2849060715e0b804) |
| B12 holder redeems tokens for SOL | received 0.0360 SOL (wSOL) for the tokens | [view](local:ea96126b92303d5b) |

## Raise C · raised in a stablecoin (tUSD, SPL token like USDC)

Currency [`F3PFEkHmAzyCt19fihMjg1YRZCg6ucGdJxEY3Ask83W5`](F3PFEkHmAzyCt19fihMjg1YRZCg6ucGdJxEY3Ask83W5) (devnet test token) · treasury [`9nYg625ZEV5sPguwPTQDJRuTGnuUKmV1zT8BKykYhMBq`](9nYg625ZEV5sPguwPTQDJRuTGnuUKmV1zT8BKykYhMBq) · funded 80.00 tUSD · tranche 1 paid 19.20 tUSD.

| Step | Result | Transaction |
| --- | --- | --- |
| C1 init_raise + DBC create_config (raised in tUSD) |  | [view](local:ab96e0ac3887a26b) |
| C2 DBC create_pool + bind_pool (on-chain checks) |  | [view](local:1a59a765e1974ea0) |
| C3 buy until the curve graduates |  | [view](local:01fecb57270c8e30) |
| C4 harvest | treasury 80.00 tUSD | [view](local:645977696055f77c) |
| C5 migrate to DAMM v2 |  | [view](local:4bb2f4c3bffdb22f) |
| C6 propose tranche 1 with evidence |  | [view](local:d1e5aa5e79c1fc42) |
| C8 settle tranche 1 | released 19.20 tUSD | [view](local:dd64347c19a9f782) |

## Raise D · raised in a tokenized stock (tNVDAx, Token-2022 like xStocks)

Currency [`CJxpbdZ6XrGv4umpkfAaJV183B4odUq22pqrrF83cEDp`](CJxpbdZ6XrGv4umpkfAaJV183B4odUq22pqrrF83cEDp) (devnet test token) · treasury [`KSyy5Befkg5wc5HZXwELHe2TQcmjg2bZeRMkUH1pY6Q`](KSyy5Befkg5wc5HZXwELHe2TQcmjg2bZeRMkUH1pY6Q) · funded 0.8000 tNVDAx · floor defense 0.0789 tNVDAx.

| Step | Result | Transaction |
| --- | --- | --- |
| D1 init_raise + DBC create_config (raised in tNVDAx) |  | [view](local:445887f48dea8a9d) |
| D2 DBC create_pool + bind_pool (on-chain checks) |  | [view](local:28c8ad3511e0b846) |
| D3 buy until the curve graduates |  | [view](local:b0273dca7ef18f64) |
| D4 harvest | treasury 0.8000 tNVDAx | [view](local:98a88ced2bcb69fd) |
| D5 migrate to DAMM v2 |  | [view](local:2cb6aae2bda949e7) |
| D6 panic sell on DAMM v2 |  | [view](local:b36aecbbe1e94544) |
| D7 defend_floor | bought back 0.0789 tNVDAx, backing +73% | [view](local:399fec5458afd18a) |

## Raise E · Meteora Bedrock's takeover clause, enforced on-chain

Treasury [`HXDKwm58x4Unm4uJXzWwaPtjJSJzpMtB9GqnQGFoHS3B`](HXDKwm58x4Unm4uJXzWwaPtjJSJzpMtB9GqnQGFoHS3B) · the program built its own TWAP from DAMM v2 price observations; a takeover had to top the treasury up so every holder redeems at TWAP +30%. TWAP 0.000625 → offer 0.000812 SOL per 1M tokens (+30%), deposit 0.6125 SOL · final state **liquidating**, new team 3d6Gx4….

| Step | Result | Transaction |
| --- | --- | --- |
| E1 init_raise + init_guard + DBC create_config |  | [view](local:b896cf3ad58af58c) |
| E2 DBC create_pool + bind_pool (on-chain checks) |  | [view](local:71004e9132092ec2) |
| E3 buy until the curve graduates |  | [view](local:5d058cdc70dae0a9) |
| E4 harvest + arm_guard (inactivity clock starts) | treasury 0.2000 SOL | [view](local:05d2702d1894bc2d) |
| E5 migrate to DAMM v2 |  | [view](local:b82d16267e69bba5) |
| E6 holder receives 5% of supply |  | [view](local:9ffccb7d65cd5de0) |
| E7.1 observe: record the DAMM v2 price for the TWAP |  | [view](local:9c9dfbbab04a6630) |
| E7.2 observe: record the DAMM v2 price for the TWAP |  | [view](local:6b0004c1b0298821) |
| E7.3 observe: record the DAMM v2 price for the TWAP |  | [view](local:7371069a6032d964) |
| E7.4 observe: record the DAMM v2 price for the TWAP |  | [view](local:76ed11432a49e85f) |
| E7.5 observe: record the DAMM v2 price for the TWAP |  | [view](local:ac8c33594e198773) |
| E8 tender_offer: takeover paying every holder TWAP +30% | TWAP 0.000625 → offer 0.000812 SOL per 1M tokens (+30%), deposit 0.6125 SOL | [view](local:4431b63784942699) |
| E9 holder redime a price de offer | received 0.0406 SOL: 30% above the TWAP | [view](local:99e98fb96c02a283) |
| E10 acquirer redeems its own tokens |  | [view](local:b650a61df18a9b0e) |

## Raise F · the team went silent, the treasury went back to holders

Treasury [`2M76u6saupEhKZbtjx96suHFepaVtVxjPC6UognpgUcE`](2M76u6saupEhKZbtjx96suHFepaVtVxjPC6UognpgUcE) · funded 0.0800 SOL · no tranche request within the guard's window (60 s on devnet), so anyone could call `declare_abandoned` · final state **liquidating**.

| Step | Result | Transaction |
| --- | --- | --- |
| F1 init_raise + init_guard (60 s inactivity) + DBC create_config |  | [view](local:a935f40a5f92973e) |
| F2 DBC create_pool + bind_pool (on-chain checks) |  | [view](local:2de7b4a382cb9d0f) |
| F3 buy until the curve graduates |  | [view](local:e23bb72fda00e27b) |
| F4 harvest + arm_guard (inactivity clock starts) | treasury 0.0800 SOL | [view](local:a427a34df4615396) |
| F6 declare_abandoned | state "liquidating" | [view](local:ea9b957ac0e32cde) |
