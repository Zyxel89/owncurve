# Mainnet study · what Meteora DBC launches promise holders

Read directly from Solana mainnet at slot 453440898 (2026-10-05) with `scripts/study.ts`: every DBC config, and every launch (virtual pool) counted against the config it uses. Raw numbers: [`mainnet-study.json`](mainnet-study.json).

**534,981 configs · 1,738,512 launches.** Launch-weighted average graduation (migration) fee: **0.7%** of the raise.

| At graduation… | Configs | Launches |
| --- | --- | --- |
| the migration fee is paid to a **wallet** (fee_claimer is a normal key) | 18,276 (3.4%) | 66,115 (3.8%) |
| the migration fee is paid to a **program** (fee_claimer is a PDA) | 1,165 (0.2%) | 2,333 (0.1%) |
| ≥ 50% of the raise is taken as migration fee | 3,010 (0.6%) | 6,594 (0.4%) |
| part of the graduated **LP is unlocked** (can be withdrawn) | 210,833 (39.4%) | 1,105,825 (63.6%) |
| someone **keeps the mint authority** | 3,105 (0.6%) | 9,621 (0.6%) |
| **all four OwnCurve guarantees hold** (PDA fee claimer, 0% to creator, no unlocked LP, no mint authority) | 180,443 (33.7%) | 177,284 (10.2%) |

Raised in: SOL 85.8% · USDC/USDT 13.4% · other tokens 0.9% of launches.

## Most used configs

| Config | Launches | Migration fee | Fee goes to | Unlocked LP | Mint authority kept |
| --- | --- | --- | --- | --- | --- |
| [`FbKf76…`](https://solscan.io/account/FbKf76ucsQssF7XZBuzScdJfugtsSKwZFYztKsMEhWZM) | 175,499 | 0% | wallet | 0% | no |
| [`38RRrt…`](https://solscan.io/account/38RRrtvAbAYnmCDjym31nvw5MYQGi3LQJQ6Gp6RbT7DU) | 59,803 | 0% | wallet | 100% | no |
| [`2CY1F7…`](https://solscan.io/account/2CY1F7f3wPM6xhjfSo4M81N9sSBkVhARf6mJnPiBSFuB) | 21,045 | 0% | wallet | 100% | no |
| [`7SXEnh…`](https://solscan.io/account/7SXEnhGRXVkR5LEE4o6xXYwcX6QJbFemMS3mbmMRHSDn) | 20,220 | 10% | wallet | 0% | no |
| [`BkoMF8…`](https://solscan.io/account/BkoMF8PzYwoVQTKcQ6uNeQrHytw1jJN6ig4JzjcKS3iF) | 12,619 | 0% | program | 0% | no |
| [`EiP739…`](https://solscan.io/account/EiP739P1dZRyqHMuqbKatyhiBr7cC1ge4iT82MCF1zcn) | 9,122 | 0% | wallet | 100% | no |
| [`J1XxMw…`](https://solscan.io/account/J1XxMw9ePUTAtsHLiaRbg9UMSXJTSy1CNjUFizdh86f3) | 8,802 | 0% | wallet | 100% | no |
| [`GybkUN…`](https://solscan.io/account/GybkUNYVNk1FZMt9myAfvpSVgoKBgaueMTvszwBN4qYx) | 7,285 | 0% | wallet | 0% | no |
| [`7UNpFB…`](https://solscan.io/account/7UNpFBfTdWrcfS7aBQzEaPgZCfPJe8BDgHzwmWUZaMaF) | 7,138 | 0% | wallet | 100% | no |
| [`48yNN4…`](https://solscan.io/account/48yNN4EC1YKsioWCmqQsZdJ8TZVaXetwncE3En5BpZ84) | 7,051 | 0% | wallet | 90% | no |

## Why it matters for OwnCurve

OwnCurve's `bind_pool` refuses any config that does not route the migration fee to its treasury PDA, gives the creator a share of it, leaves LP unlocked or keeps a mint authority. The table shows how rare that combination is today, and that wherever a large migration fee exists it almost always lands in a wallet: exactly the money OwnCurve keeps in escrow and releases per milestone.

Method notes: "wallet" means the fee_claimer key is on the ed25519 curve (it has a private key); a PDA can only be moved by its program. The migration fee is the share of the raise taken at graduation before the rest becomes DAMM liquidity; it is split between the fee_claimer and the creator by `creatorMigrationFeePercentage`.
