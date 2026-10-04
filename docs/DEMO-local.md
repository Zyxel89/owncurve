# OwnCurve · local demo

Program: [`GBHTxatkmbAX5U7G65yXzDVAZjjjyW9btGZ1DNUHtcfh`](GBHTxatkmbAX5U7G65yXzDVAZjjjyW9btGZ1DNUHtcfh) · every transaction below is real and links to the explorer.

## Raise A · tranches with evidence + price floor (SOL)

Treasury [`GD1SDhcZy8pkThdT8z5U21EPuWEMHcbXRmjP78TC4wCa`](GD1SDhcZy8pkThdT8z5U21EPuWEMHcbXRmjP78TC4wCa) · funded 0.4000 SOL · paid to the team in 3 evidence-backed tranches 0.3200 SOL (all of the payable 0.3200) · fees collected 0.0042 SOL · floor defense 0.0396 SOL · the treasury still holds 0.0446 SOL of backing for holders · final state **completed**.

| Step | Result | Transaction |
| --- | --- | --- |
| A1 init_raise + DBC create_config |  | [view](local:456e6b74f03aa413) |
| A2 DBC create_pool + bind_pool (on-chain checks) |  | [view](local:e71351a2f79dfec6) |
| A3 buy until the curve graduates | reserve 0.5000 SOL | [view](local:24e0137cf6865d0b) |
| A4 harvest | treasury 0.4000 SOL | [view](local:0944296c991ad4c7) |
| A5 collect curve trading fees (CPI) | +0.0040 SOL | [view](local:7853461a358be260) |
| A6 migrate to DAMM v2 |  | [view](local:051724532e44c6e2) |
| A7 swap on DAMM v2 |  | [view](local:d64c6643ed622400) |
| A8 claim LP fees of the treasury position (CPI) | total fees 0.0042 SOL | [view](local:fd0077a197758ed8) |
| A8b panic sell on DAMM v2 | price 0.0000203 vs backing 0.000404 SOL per 1M tokens | [view](local:490de28bda254119) |
| A8c defend_floor | bought back 0.0396 SOL, burned 473,177,901 tokens, backing +71% | [view](local:e9fef7348c345452) |
| A9.1 propose tranche 1 with evidence |  | [view](local:c005b06737552be2) |
| A9.1 settle tranche 1 | released 0.0960 / 0.3200 SOL | [view](local:26174a9af65df6f8) |
| A9.2 propose tranche 2 with evidence |  | [view](local:a8753cda52100d2a) |
| A9.2 settle tranche 2 | released 0.1920 / 0.3200 SOL | [view](local:3d26c8aee5f5db5b) |
| A9.3 propose tranche 3 with evidence |  | [view](local:73268064ad530303) |
| A9.3 settle tranche 3 | released 0.3200 / 0.3200 SOL | [view](local:7959e64fa948bbd2) |

## Raise B · holders stop a tranche → liquidation → redemption (SOL)

Treasury [`3gQNXuZCJSiXA9u9azamdojQFixnGd1o86hvjaig63LR`](3gQNXuZCJSiXA9u9azamdojQFixnGd1o86hvjaig63LR) · funded 0.2400 SOL · final state **liquidating**: the team got nothing and holders redeem against the treasury.

| Step | Result | Transaction |
| --- | --- | --- |
| B1 init_raise + DBC create_config |  | [view](local:370a56d819b962c0) |
| B2 DBC create_pool + bind_pool (on-chain checks) |  | [view](local:2767d2f4d17ae967) |
| B3 buy until the curve graduates |  | [view](local:7e44f0e01c318db1) |
| B4 harvest | treasury 0.2400 SOL | [view](local:b07135a7336f606e) |
| B6 holder receives 15% of supply |  | [view](local:b23f0cf41f61f847) |
| B7 team proposes tranche 1 |  | [view](local:85c02f3a680bf2f7) |
| B8 holder objects (locks tokens) | locked 150000000000000 tokens (base units) | [view](local:ceb18855b9e99de1) |
| B10 settle → liquidation | state "liquidating" | [view](local:7785c0bcef546ad4) |
| B11 holder unlocks voted tokens |  | [view](local:3f81bafa23afd85a) |
| B12 holder redeems tokens for SOL | received 0.0360 SOL (wSOL) for the tokens | [view](local:630c69e2e22705b8) |

## Raise C · raised in a stablecoin (tUSD, SPL token like USDC)

Currency [`F3PFEkHmAzyCt19fihMjg1YRZCg6ucGdJxEY3Ask83W5`](F3PFEkHmAzyCt19fihMjg1YRZCg6ucGdJxEY3Ask83W5) (devnet test token) · treasury [`6peaMqRKKJa5nK8y6mwrKdNjskU6QFEgj65XWuB4dhcu`](6peaMqRKKJa5nK8y6mwrKdNjskU6QFEgj65XWuB4dhcu) · funded 80.00 tUSD · tranche 1 paid 19.20 tUSD.

| Step | Result | Transaction |
| --- | --- | --- |
| C1 init_raise + DBC create_config (raised in tUSD) |  | [view](local:d4ddaf170336b31d) |
| C2 DBC create_pool + bind_pool (on-chain checks) |  | [view](local:a9df1b9ac83589dd) |
| C3 buy until the curve graduates |  | [view](local:0cc6d0734431162d) |
| C4 harvest | treasury 80.00 tUSD | [view](local:974f9c7fadcc32b2) |
| C5 migrate to DAMM v2 |  | [view](local:88095d5dba42874c) |
| C6 propose tranche 1 with evidence |  | [view](local:dd8d535086913e50) |
| C8 settle tranche 1 | released 19.20 tUSD | [view](local:1a2134ec123f01d1) |

## Raise D · raised in a tokenized stock (tNVDAx, Token-2022 like xStocks)

Currency [`CJxpbdZ6XrGv4umpkfAaJV183B4odUq22pqrrF83cEDp`](CJxpbdZ6XrGv4umpkfAaJV183B4odUq22pqrrF83cEDp) (devnet test token) · treasury [`2c5zgyRgEgNg1FsTkENn4tsAupz51WGsXWsbqokPaJTq`](2c5zgyRgEgNg1FsTkENn4tsAupz51WGsXWsbqokPaJTq) · funded 0.8000 tNVDAx · floor defense 0.0789 tNVDAx.

| Step | Result | Transaction |
| --- | --- | --- |
| D1 init_raise + DBC create_config (raised in tNVDAx) |  | [view](local:ccaa3290512265f6) |
| D2 DBC create_pool + bind_pool (on-chain checks) |  | [view](local:2f427e455ebd0b71) |
| D3 buy until the curve graduates |  | [view](local:0671a608c251a322) |
| D4 harvest | treasury 0.8000 tNVDAx | [view](local:0711a7412aa97ef8) |
| D5 migrate to DAMM v2 |  | [view](local:3a5cf2e7ecd47b8b) |
| D6 panic sell on DAMM v2 |  | [view](local:4e5a63239bc18a07) |
| D7 defend_floor | bought back 0.0789 tNVDAx, backing +73% | [view](local:2f76429ef070a420) |
