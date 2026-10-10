# Security

OwnCurve is a hackathon build deployed on **Solana devnet only**. It has not been audited.
Do not use it with real funds.

## Reporting a vulnerability

Open a private advisory: https://github.com/Zyxel89/owncurve/security/advisories/new
Please include the instruction, the accounts involved and a reproduction (a failing test in
`tests/owncurve.test.ts` is ideal). We answer in English or Spanish.

## What the program enforces

- The DBC config of every raise names the treasury PDA as `fee_claimer` and `leftover_receiver`
  (`bind_pool`), gives the creator 0% of the migration fee, locks all creator LP and leaves no
  mint authority.
- Tranches pay at most `funded − floor reserve`; the floor budget (reserve + fees) can only buy
  the token at or below its treasury backing (`defend_floor` sets `minimum_amount_out` from the
  backing) and burns what it buys.
- Holders always get a challenge window ≥ 60 s and a reject quorum ≤ 30% of circulating supply.
- Budget draws are capped by the un-advanced part of the next tranche and netted in `finalize`
  (which always receives the raise's Budget PDA), so the team can never receive more than
  `funded − floor reserve` in total.
- `observe` only accepts the DAMM v2 pool of the raise (owner, discriminator and both mints are
  checked). `tender_offer` needs ≥ 3 observations spanning half the TWAP window and a premium ≥ 10%.

## Known limitations

- Votes are locked tokens without a snapshot.
- The TWAP is a mean of permissionless observations: a sustained price manipulation across the whole
  window could move it; the window and premium are set by the team at launch.
- Tokens held by the DBC/DAMM pools count as circulating supply.
- The program is upgradeable by its deployer key while it is in devnet.

## Verifying the deployed binary

`scripts/verify.sh` downloads the program from devnet and compares its SHA-256 with a local
`anchor build` (Anchor 1.2.0, `--tools-version v1.52 --arch v0`). The program also embeds a
[security.txt](https://github.com/neodyme-labs/solana-security-txt) and publishes its IDL on-chain.
