# OwnCurve · devnet demo

Program: [`GBHTxatkmbAX5U7G65yXzDVAZjjjyW9btGZ1DNUHtcfh`](https://explorer.solana.com/address/GBHTxatkmbAX5U7G65yXzDVAZjjjyW9btGZ1DNUHtcfh?cluster=devnet) · every transaction below is real and links to the explorer.

## Raise A · tranches with evidence + price floor (SOL)

Treasury [`82pDszSzPHTuT4vfezxnATPZpMZXZ1SQKA53j5ZQYWxu`](https://explorer.solana.com/address/82pDszSzPHTuT4vfezxnATPZpMZXZ1SQKA53j5ZQYWxu?cluster=devnet) · funded 0.4000 SOL · paid to the team in 3 evidence-backed tranches 0.3200 SOL (all of the payable 0.3200) · fees collected 0.0042 SOL · floor defense 0.0396 SOL · the treasury still holds 0.0446 SOL of backing for holders · final state **completed**.

| Step | Result | Transaction |
| --- | --- | --- |
| A1 init_raise + DBC create_config |  | [view](https://explorer.solana.com/tx/2r45wpQf4Dgp8YXJYBbYF7Cv8EzH7tiXkhMypgDC3rnYHyhC4YwRGgZQFW3p4LHbqh4KeVEtQJAXdZXDWNpuRd4h?cluster=devnet) |
| A2 DBC create_pool + bind_pool (on-chain checks) |  | [view](https://explorer.solana.com/tx/5tnPgdDnyVTZzzhrhduT4afDodoHYpD5eGL2PyHcvjYVoQtg5djS6e5cnm6KoobHgDqq1ZKfHP167CSVAGwRWo7p?cluster=devnet) |
| A3 buy until the curve graduates | reserve 0.5000 SOL | [view](https://explorer.solana.com/tx/LVTcm7jmnAcDMJz1KWQpfMQan26r9p41uBK5KJs2G1MAmX8uAM4K4FCFwYHr6DeEFxMDYEqcBpep3JQuL6h3F2j?cluster=devnet) |
| A4 harvest | treasury 0.4000 SOL | [view](https://explorer.solana.com/tx/2M5gfTG7fUv29FsnFaSg3fm8FtXVk7gAWJCEk7zae5sSsBTk3BbJF6zT3pbdbQ5twubjsrUPbwVhxTespugaZMFS?cluster=devnet) |
| A5 collect curve trading fees (CPI) | +0.0040 SOL | [view](https://explorer.solana.com/tx/4ghQyWHRStnQh3xCUWzmrcPvk8NWEj5idDWnfRf5JjhxGZ3MTwYseQFMCUPDw9JNgkvg8QiFVK4pTRaiZZcH6AAE?cluster=devnet) |
| A6 migrate to DAMM v2 |  | [view](https://explorer.solana.com/tx/5YGughWgTq4xA7fuyEitUHPg5gUvhgdDS9hEoz3ZTeuY86G1RS8kdctptx4ubowqSongynGGiMtQnk2sPrQF17WY?cluster=devnet) |
| A7 swap on DAMM v2 |  | [view](https://explorer.solana.com/tx/2GEQMNDPgvjUowFpEfN81Q6asYcD6qS2QMb5goRLcT6kKBJH5K6joyzs6QiAHBV8Z2eacchT83LbcihUy9fAKwB7?cluster=devnet) |
| A8 claim LP fees of the treasury position (CPI) | total fees 0.0042 SOL | [view](https://explorer.solana.com/tx/663xjhM9uRbM8GfpSjTkKKyANMuXfxo6GqAhWKc3yCvJX3PADgiJD3HToB9zU9iCotWTvSDYS1KDh2CNEbaCE32u?cluster=devnet) |
| A8b panic sell on DAMM v2 | price 0.0000203 vs backing 0.000404 SOL per 1M tokens | [view](https://explorer.solana.com/tx/5utnZsvsKgqUTzeQ8ikcTJgbEdD7M1XVPcLJT4io9BSXQR5DrqHSrzvAxDZqDWTbTac1VyUjN5V6SMkPxv7MAAGy?cluster=devnet) |
| A8c defend_floor | bought back 0.0396 SOL, burned 473,177,901 tokens, backing +71% | [view](https://explorer.solana.com/tx/2LS1rtAmQuajsbE9hCsshMJczgJMKycv58PpVcZzTVkmoMMJxCUZTuYorBkyxh6X4ZJdyn8Qr4QUAEqtvLPYJrMB?cluster=devnet) |
| A9.1 propose tranche 1 with evidence |  | [view](https://explorer.solana.com/tx/3nq5unPbX6K3Fw9nWQyDDBLb21mjsVYmvNyHeNj4VhdZH4om93QCkb3VqZR25LDXpKfU76gvx7Q4KJ5jiKe2MwPh?cluster=devnet) |
| A9.1 settle tranche 1 | released 0.0960 / 0.3200 SOL | [view](https://explorer.solana.com/tx/32FABnnZ1W54yJVVu2fwVFQNwFt4GzdxArqnT6JcAYU7WxDwUmNmunwqVaFUm8sL31r9Gc5tVSNvdx9QMCNuCZy6?cluster=devnet) |
| A9.2 propose tranche 2 with evidence |  | [view](https://explorer.solana.com/tx/GnDTJTibh927Qr66h24TLmLv2izReCtnDNkvdG415h7WsVch76Hw5ics66hbVN2SpmkmZ1kodkjwzjCJJGMuikE?cluster=devnet) |
| A9.2 settle tranche 2 | released 0.1920 / 0.3200 SOL | [view](https://explorer.solana.com/tx/4eDXYWxu98yae7VbFU4cQXiCqZRP6Lh4a7CFDeuhYDLyD1aEH2K1MW72Yda1mXjx6nMeR9fiGKeXbqh7A13Yphi?cluster=devnet) |
| A9.3 propose tranche 3 with evidence |  | [view](https://explorer.solana.com/tx/34aZihzRu8pwYyTaZRAuiLnh1X55EjQESkLPg6nNTgaUregYiGEYYpCJhYRULxWV9XErn7NraXAPJk9C54QX2Qor?cluster=devnet) |
| A9.3 settle tranche 3 | released 0.3200 / 0.3200 SOL | [view](https://explorer.solana.com/tx/2E1HL6xNxR3YK9wJvz8tKUm5p8Hd1QwaEGapqvFE6yVz7F8JczwdkyNPjWB9APtpWhnW4NgbsqXeh3ynqvekJ3EN?cluster=devnet) |

## Raise B · holders stop a tranche → liquidation → redemption (SOL)

Treasury [`E3oa8mHXMNYqmVqXnVpNbBT6bYF5hdZxCUas3UDP42Ay`](https://explorer.solana.com/address/E3oa8mHXMNYqmVqXnVpNbBT6bYF5hdZxCUas3UDP42Ay?cluster=devnet) · funded 0.2400 SOL · final state **liquidating**: the team got nothing and holders redeem against the treasury.

| Step | Result | Transaction |
| --- | --- | --- |
| B1 init_raise + DBC create_config |  | [view](https://explorer.solana.com/tx/3RbdTNtixHPaLnSxYz6Tvh7Yn8a2wr3fo7ukVtQdivhSCke29yVFiYGJAoih4GVP3eDeC9VhFheuXKbjQbxhcqkj?cluster=devnet) |
| B2 DBC create_pool + bind_pool (on-chain checks) |  | [view](https://explorer.solana.com/tx/3qcy7tmCnkzB1XyT8MKFGf5RnhPXcR94hEXwcGmbhj3uyK9qAVKzHafYgKKQSpfMn3aB62Zf5usGm8hDxtKVU5TV?cluster=devnet) |
| B3 buy until the curve graduates |  | [view](https://explorer.solana.com/tx/57mEJA5BXTJgLkSu7zGU4RSYEVDNSpRFPXnpYGNDxVTCmxZkCcz4EHPCe4RPAAvTDis1BLuhXJ6xWak86Eai88zW?cluster=devnet) |
| B4 harvest | treasury 0.2400 SOL | [view](https://explorer.solana.com/tx/3qie4X4UTNkqgzeXBXYCbxM3TFhQN2weyNU1BpFatoKqTgcgKgVihDVJchc2ffeyCgDHyNmdyiiNsszL53HFLuQh?cluster=devnet) |
| B6 holder receives 15% of supply |  | [view](https://explorer.solana.com/tx/2aM1yt84yEjCJi1Yenc4FBfWLdvYKAk9iPzcYUeH6aiu9mRJHdD1VrNk628BVCFefHo5uH6pWLEvbB8HG44j8Hyz?cluster=devnet) |
| B7 team proposes tranche 1 |  | [view](https://explorer.solana.com/tx/4EKskec297g8JwdxB5RZUXrfUi5hVr66W61DzCbW82NrYze8DeaJcccnJs8oQPEFpu2SXizZJywH7VQUd43r47jV?cluster=devnet) |
| B8 holder objects (locks tokens) | locked 150000000000000 tokens (base units) | [view](https://explorer.solana.com/tx/wASMTfvmQFWVhJEJmC6qcMgrdUQfNYF63qgwH93ZBPQZGM3A8fmMJxs4jNt7o3qUuuTEjYvMTZeYd18yXTLited?cluster=devnet) |
| B10 settle → liquidation | state "liquidating" | [view](https://explorer.solana.com/tx/GjN1VnurKKoLx2deqS5t3mqzH18CQKZnkenRYupPb9m8Fsk3orZzk1jQbH2eJ2pDc6uYV5LMpMp93W48JoXbHAE?cluster=devnet) |
| B11 holder unlocks voted tokens |  | [view](https://explorer.solana.com/tx/4mCXnKe2nD3x8swH7pvWAsCdhuHRRM3TEAAUWRKicKqpvTYCt2B1axPaCdUD7rPnnb4qLPeRvtHaymDcx94GQToK?cluster=devnet) |
| B12 holder redeems tokens for SOL | received 0.0360 SOL (wSOL) for the tokens | [view](https://explorer.solana.com/tx/2dubvuXVXvoF7C4wzaYiquQ6Ur59SLokuhdoDSPE5uPg1eTZ2fjsxZAycgiPxCqgV6bbBud4oSgxY5Kop46mFEkm?cluster=devnet) |

## Raise C · raised in a stablecoin (tUSD, SPL token like USDC)

Currency [`F3PFEkHmAzyCt19fihMjg1YRZCg6ucGdJxEY3Ask83W5`](https://explorer.solana.com/address/F3PFEkHmAzyCt19fihMjg1YRZCg6ucGdJxEY3Ask83W5?cluster=devnet) (devnet test token) · treasury [`sNFBrJENS2GvTWmo5P16A7vPKzggFd3YwwaKhFxK4FM`](https://explorer.solana.com/address/sNFBrJENS2GvTWmo5P16A7vPKzggFd3YwwaKhFxK4FM?cluster=devnet) · funded 80.00 tUSD · tranche 1 paid 19.20 tUSD.

| Step | Result | Transaction |
| --- | --- | --- |
| C1 init_raise + DBC create_config (raised in tUSD) |  | [view](https://explorer.solana.com/tx/3qVpqr4sjpkWGvZcmiFV2UggiwCzrn8cMM7cEuHm3wZGuUwjj1ZQQKMQvRBB8YcCDZxzXjaQhTk4PnHHaDs5rSpz?cluster=devnet) |
| C2 DBC create_pool + bind_pool (on-chain checks) |  | [view](https://explorer.solana.com/tx/4fKLZyD8eEqSgXKL9hVzdQqdBQLApRVP85RFE3LACzAPKLQ31DYEDaKZPoDxvTnQPSABS6Fx54g7ZqcQx8ay9ERV?cluster=devnet) |
| C3 buy until the curve graduates |  | [view](https://explorer.solana.com/tx/47eGcTt9D5Ff3GGxbYLxcceWtcrDmEffYyRi5ato8DhgqWHbmQxyqz1nARr2uqpjHCSwJgEZMem1jCrX1kw57Qmh?cluster=devnet) |
| C4 harvest | treasury 80.00 tUSD | [view](https://explorer.solana.com/tx/43kGdD7hP9JUfX42ArD72UmqxNqNEjuzNvmNPi4c7nvryMuNdub2zjMKw88mSAmq3h9aJUShoWXoWaEVNRoAPARD?cluster=devnet) |
| C5 migrate to DAMM v2 |  | [view](https://explorer.solana.com/tx/25gkLpVVBTFQbyBfek2665F8u58bBNKyLRkzV5GiBSEXwesdU2h9iPV6dhK4LJZr3uhxuBFVs6G8j5Xu2K7cWjfE?cluster=devnet) |
| C6 propose tranche 1 with evidence |  | [view](https://explorer.solana.com/tx/2284uLm8CB9P4vea6wbN2FutbNDf6sXSKqvrT1PznFRrNWBVvgBJpAnc3jjBpwTKk8GEVGXR3Gevnu19uqMjGKEN?cluster=devnet) |
| C8 settle tranche 1 | released 19.20 tUSD | [view](https://explorer.solana.com/tx/3y4oNHvvo5CL76QieVRoj2Ko1YbESGRKjxjMWMpQvjazUAT7wi77GdSbQ9Q8nLJSHHj6oq3uubTs65HWBeKyMQjc?cluster=devnet) |

## Raise D · raised in a tokenized stock (tNVDAx, Token-2022 like xStocks)

Currency [`CJxpbdZ6XrGv4umpkfAaJV183B4odUq22pqrrF83cEDp`](https://explorer.solana.com/address/CJxpbdZ6XrGv4umpkfAaJV183B4odUq22pqrrF83cEDp?cluster=devnet) (devnet test token) · treasury [`57Y7NSidN1VoNRxQ9gXCyqaCHCws5pYh1yer6hKfA4c1`](https://explorer.solana.com/address/57Y7NSidN1VoNRxQ9gXCyqaCHCws5pYh1yer6hKfA4c1?cluster=devnet) · funded 0.8000 tNVDAx · floor defense 0.0789 tNVDAx.

| Step | Result | Transaction |
| --- | --- | --- |
| D1 init_raise + DBC create_config (raised in tNVDAx) |  | [view](https://explorer.solana.com/tx/5fQh1wLgmpM84mv562PhdtxK5m4ehC37Qqa9KHxmSffaZb7B4xQ7iChMhVREZWcaNin1QpKrZJwRwb4wRTAjFf4G?cluster=devnet) |
| D2 DBC create_pool + bind_pool (on-chain checks) |  | [view](https://explorer.solana.com/tx/ys2R2mjsXxywJwXP4bi4gG7K4w6o5Kj8UdVWBzWnocj4oWcNLcU66n6bBg5GLYvVYUZSTjP3Z8PtjRB95HVm4P4?cluster=devnet) |
| D3 buy until the curve graduates |  | [view](https://explorer.solana.com/tx/2F3jLBLr5Eda4UatcZcYKo6LuQLb2MCSe9GcxYdxKJS1sL79mLKsed9hGGrE9taokCH9DcW5hA8NrT4STwtPu3kY?cluster=devnet) |
| D4 harvest | treasury 0.8000 tNVDAx | [view](https://explorer.solana.com/tx/2gTDMsVbYAzxFK6vuAR5CbTeDcVUmmqR6UsMhz6DHy4pvjJjcN2Fz41m5Xv8WHYWn5CNCFBZ7KAn18ZLY3vH5UBy?cluster=devnet) |
| D5 migrate to DAMM v2 |  | [view](https://explorer.solana.com/tx/3fcBnmednS7qi27Ug8KeqYUG6EAMGBkLhhx8P9UsfNw1E5E31hvu1xiGEUHQMjaXbM86FPuZkpvkSLgGfPJkPwPp?cluster=devnet) |
| D6 panic sell on DAMM v2 |  | [view](https://explorer.solana.com/tx/9ctKvyQiHX9QWYatRgpHGvgHAwFJ2CL1bvLv457K5ucB3PbKcSdSQrPMGHKnhZd6YEBEd1gpH7ETHCT2V1Feejc?cluster=devnet) |
| D7 defend_floor | bought back 0.0789 tNVDAx, backing +73% | [view](https://explorer.solana.com/tx/4eJ3pUd64Dd7mmN3CXxCqd78QrrcjRXoaps1K9dirFcdnC62GcCsgy9ZLyXaunFtXqtK57mq2UA4ct5fGg3NtUZx?cluster=devnet) |

## Raise E · Meteora Bedrock's takeover clause, enforced on-chain

Treasury [`12US696pXxmuLWwv94sEKFiteeN7V133VS7XUDKek7vB`](https://explorer.solana.com/address/12US696pXxmuLWwv94sEKFiteeN7V133VS7XUDKek7vB?cluster=devnet) · the program built its own TWAP from DAMM v2 price observations; a takeover had to top the treasury up so every holder redeems at TWAP +30%.  · final state **liquidating**, new team AGxjAi….

| Step | Result | Transaction |
| --- | --- | --- |
| E1 init_raise + init_guard + DBC create_config |  | [view](https://explorer.solana.com/tx/49hacWtEKcEkWjYV6raqMobPYwthpEMfdonD5iadYMCL5vyvJfw7sTz8PuLkXxTWXRFNQ6nEkH3tzcJHnUuWfr3w?cluster=devnet) |
| E2 DBC create_pool + bind_pool (on-chain checks) |  | [view](https://explorer.solana.com/tx/L7LYCCgzFy9cYh99aR6dvnaKJU5Qoh91yQuk6qSMoeJ1hp6RpyChLkVcabfAvRiEwDtZCTtoep6BWUgmp3WNG4Y?cluster=devnet) |
| E3 buy until the curve graduates |  | [view](https://explorer.solana.com/tx/5LPWfXpSEg8ygKxx1yXWAX8pbVS3gxs2mhnNqugG54ZXQ3DSmzJZKe76UY1yDa1i6RWe3uRkYa8Rz2jK3DtesNqt?cluster=devnet) |
| E4 harvest + arm_guard (inactivity clock starts) | treasury 0.2000 SOL | [view](https://explorer.solana.com/tx/5EXyjBPDmAxAbdWztH8fJhBcTBGiVEp9vhMT63RJzBVoNT8MPCsjuYAmaJ9eyBKoGeCDNH3Wo9fSG9gsLZtC42VB?cluster=devnet) |
| E5 migrate to DAMM v2 |  | [view](https://explorer.solana.com/tx/4sxft5XMwpbQBREt8RfxdMJgtrtna2789cC6qBAAxw5vMnxfcmj7r2bpS2agYon5SyhgC99Hhr2aVyJ77ZXdP6yp?cluster=devnet) |
| E6 holder receives 5% of supply |  | [view](https://explorer.solana.com/tx/4oBGukbdwg7McMhaa9coWQPrkBFcxT1WLoahEffcmiY98DrPM1wAFvqoN9JQm9dFh5cKPR1YszUzRCCsHHHbP7WJ?cluster=devnet) |
| E7.1 observe: record the DAMM v2 price for the TWAP |  | [view](https://explorer.solana.com/tx/3c9htoKUGVJXwiWokgPmWv7miCS9yPQN88fGuRFbcMCmJeEpN5LDvBLiVAKq2xBQSB9zRMxkGYNmSKsxGHiKPXmo?cluster=devnet) |
| E7.2 observe: record the DAMM v2 price for the TWAP |  | [view](https://explorer.solana.com/tx/vicxcZAGW9A4ASfsWeC7zBJaGbBtNZ81vrLJe8jj8NDUBCdo4GjoZNz74V7kENwbuvBoXWEvPkmm4wFgALVNknf?cluster=devnet) |
| E7.3 observe: record the DAMM v2 price for the TWAP |  | [view](https://explorer.solana.com/tx/28ofMim9g1UzGBnQkhErwgmuEWXkWCTprqmswGUu3Lio4rivVJkGNmFBs8Zdn5YkLAd6bwuvKQb8exDpydp2Zv1h?cluster=devnet) |
| E7.4 observe: record the DAMM v2 price for the TWAP |  | [view](https://explorer.solana.com/tx/5uqVHMEc2rYajNfA23P5bZiPoeuXmqDw3PW662hzAbDmcB3TAibYKMmBZYjPkmEVhKYUCqBUpV5he2AbeZDFLaVs?cluster=devnet) |
| E7.5 observe: record the DAMM v2 price for the TWAP |  | [view](https://explorer.solana.com/tx/5F4yWx66HzDif1TCXQxcc3g6VPS7SXLWhcCErLi5c1RXhTZj8nJHjTWSuSQpfD4kf9GuKD2MemtnvQvpCHgiKYBb?cluster=devnet) |
| E8 tender_offer: takeover paying every holder TWAP +30% | TWAP 0.000625 → offer 0.000812 SOL per 1M tokens (+30%), deposit 0.6125 SOL | [view](https://explorer.solana.com/tx/2nnSY2pbdNaraRX2k4AKzMtk7ZVJeRzPnQ6jZAzJWk5AznNBezL9JNy2zjRbfdmdRnrsrixiraqrDCaibrwPVj6y?cluster=devnet) |
| E9 holder redime a price de offer | received 0.0406 SOL: 30% above the TWAP | [view](https://explorer.solana.com/tx/3KhRtTTWfvHJHYDcqhEQFVgDzX5r3baNjcBCwhzZ2NgQJD5zTJWDQV35ooQAxifQDC3JF65Zjhd33XVrmXci5cRQ?cluster=devnet) |
| E10 acquirer redeems its own tokens |  | [view](https://explorer.solana.com/tx/23rr8BzkimHPGs37CUDpVMpvypwtZCmjo3wg4oQHEjL7PeUZBnppAfZyqPK1jrqhYu7yk1xiShTbq2a6y5Qscpid?cluster=devnet) |

## Raise F · the team went silent, the treasury went back to holders

Treasury [`ELQqDD2h2P5mKuz4JjWNW4BmFKuiFUU1iJ3KJXt32ABZ`](https://explorer.solana.com/address/ELQqDD2h2P5mKuz4JjWNW4BmFKuiFUU1iJ3KJXt32ABZ?cluster=devnet) · funded 0.0800 SOL · no tranche request within the guard's window (60 s on devnet), so anyone could call `declare_abandoned` · final state **liquidating**.

| Step | Result | Transaction |
| --- | --- | --- |
| F1 init_raise + init_guard (60 s inactivity) + DBC create_config |  | [view](https://explorer.solana.com/tx/316XbKwTk3tqiVFGUkt5yZio64YqskEt1h7mvFsjpad7k9GGtYf9P9BEi8q4oiEtjPQiWBcv8Jo3LkrCWvshNpRn?cluster=devnet) |
| F2 DBC create_pool + bind_pool (on-chain checks) |  | [view](https://explorer.solana.com/tx/w8CtNqvMqKudeaJy4vvLFyDeG6TyVcZMhDnVzpj76JkA7G14M43Y2s8TFrAjJfD4uz3Erq7hEcXSgNzNvEggEyb?cluster=devnet) |
| F3 buy until the curve graduates |  | [view](https://explorer.solana.com/tx/2etvgdTwfm7DqoxkLSbRrzsKEeQkL9oTMMcmYMBLz26f5BR8kC5aAW8GbSsGiRT12dUf2bY3zpA1fs3ESf4aYfNg?cluster=devnet) |
| F4 harvest + arm_guard (inactivity clock starts) | treasury 0.0800 SOL | [view](https://explorer.solana.com/tx/2tUYicHYYeXf3dAx2eaFwsKjSedseikRGjLQKwdABUSzaWe2Ur9RT4effbjJEw8MQ82vD14ip1EysrewpXyA8fTg?cluster=devnet) |
| F6 declare_abandoned | state "liquidating" | [view](https://explorer.solana.com/tx/3VDYMcqqCz8id1imVSesNatF8mfY4rtXJ1h72Tkhkd914oQsKskp9Af6WhCRvrUG9pSxSoZPERxDdr5Rw2nHA95u?cluster=devnet) |

## Raise G · operating budget, kept alive by the keeper

Treasury [`F7aNPaZdhARzpFF1g4BjmzCvVfsqGfBUtLdQxkgicKMt`](https://explorer.solana.com/address/F7aNPaZdhARzpFF1g4BjmzCvVfsqGfBUtLdQxkgicKMt?cluster=devnet) · the team draws a bounded budget every 10 min as an advance on its next tranche; tranche 1 was requested and the public keeper settles it, records the DAMM v2 price for the TWAP every run and would return the treasury if the team went silent for 7 days.

| Step | Result | Transaction |
| --- | --- | --- |
| G1 init_raise + init_guard + DBC create_config + presupuesto |  | [view](https://explorer.solana.com/tx/CQMDbHAAgY1YSo1158RqcD5u9f2URRJYXYa8xAS2j1VD2iz2uwkBuvN5yTU2Jwy8BYzAq3EiBfQbVnjYTbBgFPW?cluster=devnet) |
| G2 DBC create_pool + bind_pool (on-chain checks) |  | [view](https://explorer.solana.com/tx/2Ub9wipZdn6Kk5XDCr61EP92DU28mTZe25rXaNNJ27mQ11sT7gj9R42e971B9SvugrkczfABXHKXF7c36ijQWjrH?cluster=devnet) |
| G3 buy until the curve graduates |  | [view](https://explorer.solana.com/tx/4gWFRucgFJoY633ukCLvHnrtrQnjdSmbQom7y5VdvLQMZxuBECVDmWi8esnSdCazzgm7nLdkAbQSYXWau7uiU8rj?cluster=devnet) |
| G4 harvest + arm_guard (inactivity clock starts) | treasury 0.1600 SOL | [view](https://explorer.solana.com/tx/357bh1TJU7KAdujQeTsiPVCBgyJoAqLwCT96RLHntftgFaZMRTveJd2iNg3t3ARryD78taJ1K5KqKGwQhbyKHCwV?cluster=devnet) |
| G5 migrate to DAMM v2 |  | [view](https://explorer.solana.com/tx/3eQeoAa4tbJcpJM4j9xH96XR8ccCjw51gu3imJW2N7seghv361zDr2MuiEprVo3sH6K8DGbbz3y7JYzTzpnVEJVa?cluster=devnet) |
| G6 draw_budget | budget 0.0050 SOL, advanced on tranche 1 | [view](https://explorer.solana.com/tx/3Da96xLaQ7CzXRJEmGjSPSyJZSB3eiGdgFYSGJ9rUJNRApDX9SaP2MrK9YXsAA1ekTzpbzPgCRSchEgqztpSVvb?cluster=devnet) |
| G7 propose tranche 1 with evidence (lo liquida el keeper) |  | [view](https://explorer.solana.com/tx/3aGxrMDt1nMhkUnxiYZ4rB1d3Y3658Na4mipoZTxddDNXtaczwriWPY7WvW7pxMuWL7kJ4rUdR1kiCNub5j5Ly8X?cluster=devnet) |
