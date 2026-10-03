---
name: owncurve
description: Launch, inspect and govern OwnCurve ownership-coin raises on Meteora DBC + DAMM v2 (Solana). Use when the user wants to launch a token whose raise is paid to the team in milestone tranches, check a raise, review a team's milestone evidence, object to a tranche, redeem from a liquidated treasury, or defend the price floor.
---

# OwnCurve

OwnCurve turns a Meteora Dynamic Bonding Curve launch into an ownership coin. At graduation
the raise goes into an on-chain treasury (a program PDA, not a wallet). The team is paid one
milestone tranche at a time; every request carries a link to the delivered work and a SHA-256
committed on-chain. Holders can lock tokens to object; if objections reach quorum the treasury
becomes a pro-rata redemption pool. Part of the treasury is a price floor: when the token trades
on DAMM v2 below what the treasury holds per token, anyone can make the treasury buy it back
and burn it.

## Setup

```bash
git clone https://github.com/Zyxel89/owncurve && cd owncurve && npm ci
export RPC_URL=https://api.devnet.solana.com   # any devnet RPC
export WALLET=~/.config/solana/id.json          # keypair that signs
npx tsx scripts/cli.ts help
```

Every command prints JSON. Below, `owncurve` means `npx tsx scripts/cli.ts`.

## Rules for the agent

1. **Read before acting.** Run `owncurve show <config>` first. Its `can` array lists exactly
   the actions this wallet can take right now; do not try anything that is not in it.
2. **Writes are simulated unless `--yes` is passed.** Run the command without `--yes`, check
   `wouldSucceed`, show the user what will happen, and only then repeat it with `--yes`.
3. **Ask the user before** `launch`, `buy`, `object` and `redeem`: they move the user's money or
   lock their tokens. `harvest`, `collect-fees`, `migrate`, `settle` and `defend-floor` are
   permissionless upkeep that only moves funds into the treasury or follows its rules; you can
   run them when `can` lists them, but say what you did.
4. Report amounts in SOL and link the `explorer` URL from the result.
5. On `{"ok": false, "error": "<Name>"}` explain the error in plain words (table below); do not retry blindly.

## Commands

| Command | Who | What |
| --- | --- | --- |
| `list` | anyone | All raises with state, funded and treasury SOL |
| `show <config>` | anyone | Tranches, pending proposal + evidence, price vs backing, wallet, `can` |
| `launch --name N --symbol S [--threshold 0.5] [--treasury 80] [--tranches 30,30,40] [--window 60] [--quorum 10] [--floor 20]` | team | New raise; returns `config` |
| `propose <config> --evidence URL [--note TEXT]` | team | Request the next tranche; stores `sha256(note or URL)` |
| `buy <config> --sol X` | anyone | Buy on the bonding curve |
| `harvest <config>` | anyone | Move the graduated raise into the treasury |
| `migrate <config>` | anyone | Graduate the pool to Meteora DAMM v2 |
| `collect-fees <config>` | anyone | Curve trading fees → treasury |
| `settle <config>` | anyone | After the window: pay the tranche, or open redemptions if quorum objected |
| `defend-floor <config> [--sol X]` | anyone | Treasury buys back below backing and burns |
| `object <config> [--amount T]` | holder | Lock tokens against the pending tranche (default: all) |
| `unlock <config>` | holder | Return voted tokens after settlement |
| `redeem <config> [--amount T]` | holder | In liquidation: burn tokens for a pro-rata share of the treasury |

## Workflows

### Watch a raise for a holder ("guardian")

1. `owncurve show <config>`. If `proposal` is null, nothing is pending.
2. If a proposal is pending, open `proposal.evidenceUri` and check that it shows the work the
   milestone promised. If the team published the note text, verify it:
   `printf '%s' "<note>" | sha256sum` must equal `proposal.evidenceSha256`.
3. Tell the user what was delivered, what is missing, `secondsLeft`, and how many tokens object
   against `quorumTokens`. Recommend objecting only with a concrete reason (link missing,
   unrelated to the milestone, hash mismatch). If the user agrees: `owncurve object <config>` (dry run), then `--yes`.
4. After the window: `owncurve settle <config> --yes`, then `owncurve unlock <config> --yes`.
5. If `state` became `liquidating`, offer `owncurve redeem <config>`; `backing.solPerMillionTokens` tells what it pays.

### Launch for a team

1. Agree the tranches with the user (1–5, sum 100), treasury share (50–99%), window (≥ 60 s),
   quorum (≤ 30%) and floor reserve (0–50%).
2. `owncurve launch ...` without `--yes`, then with `--yes`. Share the `config` and the web link
   `https://<app>/#/raise/<config>`.
3. For each milestone: publish the work, then `owncurve propose <config> --evidence <url> --note "<what shipped>" --yes`.

### Keep the floor

`owncurve show <config>`: if `market.belowBacking` is true and `can` contains `defend-floor`,
run `owncurve defend-floor <config> --yes`. The program refuses to pay more than the backing
per token, so the buyback always raises the backing of the remaining tokens.

## Errors

| Error | Meaning |
| --- | --- |
| `NotTeam` | Only the team wallet can request tranches |
| `InvalidState` | Not possible in the raise's current state (check `state`) |
| `ChallengeWindowOpen` | Objections are still open; wait `secondsLeft` |
| `ChallengeWindowClosed` | Too late to object |
| `NoActiveProposal` | No tranche is pending |
| `ProposalActive` | A tranche is already pending; settle it first |
| `VoteStillLocked` | Votes unlock only after the tranche is settled |
| `ZeroAmount` | The wallet has no tokens for this action |
| `InvalidEvidence` | Evidence URL empty or longer than 160 characters |
| `FloorBudgetExceeded` | Asked for more than the floor budget (reserve + fees − spent) |
| `NothingToDefend` / slippage | Price is not below backing |
| `InvalidGovernance` / `InvalidMilestones` | Launch parameters out of bounds |
