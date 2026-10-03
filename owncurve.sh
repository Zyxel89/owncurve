#!/usr/bin/env bash
# =============================================================================
#  OwnCurve — script de trabajo (se sobreescribe en cada entrega)
#  Fase actual: F4B  Mejoras para ir a por el 1.er puesto
#    B.1 piso de precio en cadena: defend_floor (recompra bajo el respaldo vía CPI a DAMM v2 + quema)
#    B.2 hitos con evidencia: cada tramo guarda enlace + SHA-256 en cadena
#    B.3 interfaz: panel precio vs respaldo, botón de recompra, formulario de evidencia
#    B.4 Agent Skill (skills/owncurve/SKILL.md) + CLI JSON con simulación por defecto
#    B.5 demo pública: workflow de GitHub Pages (se activa al publicar el repo en F5)
#    B.6 programa actualizado en devnet (12 instrucciones, binario más pequeño) y demo nueva
#
#  Uso:   cd ~/owncurve && bash owncurve.sh
#  Usa la RPC configurada en la CLI de Solana (tu dRPC), o RPC_URL=... si la pasas.
#  Reanudable: si algo falla, vuelve a ejecutarlo; no repite pasos ni gasta SOL de nuevo.
#  Log: ~/owncurve/logs/F3.log  ·  Tarda ~15 min (tests + demo con 4 ventanas de 60 s)
# =============================================================================
set -Eeuo pipefail

PHASE="F4B"
REPO_DIR="$HOME/owncurve"
LOG_DIR="$REPO_DIR/logs"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/$PHASE.log"
: > "$LOG"

G='\033[1;32m'; R='\033[1;31m'; Y='\033[1;33m'; B='\033[1;34m'; N='\033[0m'
ok()   { echo -e "${G}  ✔ $*${N}"; }
warn() { echo -e "${Y}  ! $*${N}"; }
fail() { echo -e "${R}  ✘ $*${N}"; echo -e "${R}    Revisa el log: $LOG${N}"; exit 1; }
step() { echo -e "\n${B}==> $*${N}"; }
run()  {
  local desc="$1"; shift
  echo "+ $*" >> "$LOG"
  if "$@" >> "$LOG" 2>&1; then ok "$desc"; else fail "$desc"; fi
}
trap 'echo -e "${R}Error inesperado en la línea $LINENO. Log: $LOG${N}"' ERR

[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
export PATH="$HOME/.local/share/solana/install/active_release/bin:$HOME/.avm/bin:$PATH"
sol() { awk "BEGIN{printf \"%.2f\", $1/1000000000}"; }

echo -e "${B}OwnCurve · $PHASE · $(date '+%Y-%m-%d %H:%M')${N}"

# =============================================================================
step "1/7 Comprobaciones"
# =============================================================================
for t in solana anchor cargo node npm jq git; do
  command -v "$t" >/dev/null 2>&1 || fail "Falta '$t'. Abre una terminal nueva o 'source ~/.zshrc'"
done
cd "$REPO_DIR"
[ -f target/deploy/owncurve-keypair.json ] || fail "Falta la clave del programa. Ejecuta F1.1"
[ -f app/vite.config.ts ] || fail "Falta el código de F4. Ejecuta primero el script de F4"
RPC="${RPC_URL:-$(solana config get | awk '/RPC URL/{print $3}')}"
case "$RPC" in *devnet*) ;; *) fail "La RPC ($RPC) no parece de devnet. Usa: RPC_URL=<tu RPC de devnet> bash owncurve.sh";; esac
ok "RPC devnet: ${RPC%%/solana-devnet/*}/…"

# =============================================================================
step "2/7 Código: programa, cliente, CLI, Agent Skill, interfaz y tests"
# =============================================================================
mkdir -p scripts/lib docs skills/owncurve tests/e2e .github/workflows
cat > 'Cargo.toml' <<'OWNCURVE_EOF'
[workspace]
members = ["programs/*"]
resolver = "2"

[profile.release]
overflow-checks = true
lto = "fat"
codegen-units = 1
opt-level = "s"
OWNCURVE_EOF

cat > '.gitignore' <<'OWNCURVE_EOF'
target/*
!target/idl/
logs/
node_modules/
.anchor/
test-ledger/
.owncurve/
local/
.deps/
app/dist/
app/.env.local
OWNCURVE_EOF

cat > 'package.json' <<'OWNCURVE_EOF'
{
  "name": "owncurve",
  "private": true,
  "type": "commonjs",
  "scripts": {
    "f1": "tsx scripts/f1.ts --migrate",
    "demo": "tsx scripts/demo.ts",
    "test": "CLUSTER=local tsx --test tests/owncurve.test.ts",
    "e2e": "tsx tests/e2e/ui.e2e.ts",
    "app": "vite --config app/vite.config.ts",
    "app:build": "vite build --config app/vite.config.ts",
    "owncurve": "tsx scripts/cli.ts",
    "test:cli": "tsx --test tests/cli.test.ts"
  },
  "dependencies": {
    "@anchor-lang/core": "1.2.0",
    "@fontsource-variable/bricolage-grotesque": "^5.3.0",
    "@fontsource/public-sans": "^5.3.0",
    "@meteora-ag/dynamic-bonding-curve-sdk": "1.5.12",
    "@solana/spl-token": "0.4.15",
    "@solana/wallet-adapter-base": "^0.9.28",
    "@solana/wallet-adapter-react": "^0.15.40",
    "@solana/web3.js": "1.99.0",
    "bn.js": "5.2.5",
    "react": "^18.3.1",
    "react-dom": "^18.3.1"
  },
  "devDependencies": {
    "@types/node": "^22.20.5",
    "@types/react": "^18.3.31",
    "@types/react-dom": "^18.3.7",
    "@vitejs/plugin-react": "^6.1.1",
    "bs58": "^4.0.1",
    "litesvm": "0.1.0",
    "playwright-core": "^1.63.0",
    "tsx": "4.23.15",
    "typescript": "5.9.3",
    "vite": "^8.3.2",
    "vite-plugin-node-polyfills": "^0.28.0"
  }
}
OWNCURVE_EOF

cat > 'README.md' <<'OWNCURVE_EOF'
# OwnCurve

Ownership coins on Meteora's Dynamic Bonding Curve (DBC).

A raise is a normal DBC launch whose config names OwnCurve's treasury PDA as
`fee_claimer` and `leftover_receiver`. At graduation the DBC migration fee (up to
99% of the raise) is pulled into an on-chain treasury instead of a wallet. The team
is paid in milestone tranches; holders can lock tokens to reject a tranche, and a
rejection that reaches quorum turns the treasury into a pro-rata redemption pool.
After graduation the treasury also owns the DAMM v2 LP position, so it keeps earning
trading fees forever.

Two things no other launchpad does on-chain:

- **Evidence-backed milestones.** Every tranche request stores a link to the delivered work and
  the SHA-256 of what the team claims it shipped. Holders (or their AI agent) review it during
  the challenge window.
- **A price floor that defends itself.** A share of the treasury (default 20%) plus every fee it
  earns is never paid to the team. When the token trades on DAMM v2 below the SOL the treasury
  holds per token, anyone can call `defend_floor`: the treasury buys tokens back through a CPI
  swap, **the program refuses to pay more than the backing**, and the tokens are burned, so the
  backing of every remaining token goes up.

Built for the Colosseum Crypto World's Fair — "Best use of Meteora's DBC" sidetrack.

## Lifecycle

```
Pending --bind_pool--> Bonding --harvest (CPI)--> Funded
Funded --propose_release(evidence) + reject votes--> finalize
    quorum not reached -> tranche to team -> Funded (next milestone) / Completed (last)
    quorum reached     -> Liquidating -> redeem (burn tokens, receive NAV share)
Any time after launch: collect_trading_fees, collect_surplus, claim_lp_fees -> treasury
After graduation, price < backing: defend_floor -> DAMM v2 swap (treasury pays) -> burn
```

## Instructions

| Instruction | Caller | What it does |
| --- | --- | --- |
| `init_raise` | team | Milestone tranches (sum 10000 bps), min treasury %, challenge window, reject quorum, floor reserve (≤ 50%) |
| `bind_pool` | anyone | Validates the live DBC config + pool before anyone buys (see guarantees) |
| `harvest` | anyone | CPI `withdraw_migration_fee` signed by the treasury PDA |
| `collect_trading_fees` | anyone | CPI `claim_trading_fee`: partner share of curve fees → treasury |
| `collect_surplus` | anyone | CPI `partner_withdraw_surplus` → treasury |
| `claim_lp_fees` | anyone | CPI DAMM v2 `claim_position_fee` for the treasury-owned position |
| `propose_release` | team | Opens a challenge window for the next milestone, with evidence URL + SHA-256 |
| `reject` | holder | Locks base tokens in escrow as a reject vote |
| `finalize` | anyone | Pays the tranche, or switches to liquidation if quorum was met |
| `withdraw_vote` | holder | Returns locked tokens after finalize |
| `redeem` | holder | In liquidation: burn tokens, receive a pro-rata share of the treasury |
| `defend_floor` | anyone | CPI DAMM v2 `swap` paid by the treasury, only at or below backing; bought tokens are burned |

## On-chain guarantees (enforced by `bind_pool` / `init_raise`)

- `fee_claimer` and `leftover_receiver` of the DBC config are the treasury PDA: only this program can move the raise.
- The creator gets 0% of the migration fee and its DAMM v2 LP is 100% permanently locked (no liquidity rug).
- The creator never holds the mint authority (no infinite mint).
- The migration fee routed to the treasury is at least the raise's `min_treasury_pct` (≥ 50%).
- Holders always get a challenge window of ≥ 60 s, and blocking a tranche never needs more than 30% of supply.
- Fees, surplus and LP fees can only be sent to treasury-owned token accounts.
- Tranches pay at most `funded − floor reserve`; the floor budget (reserve + fees) can only buy back at or below backing.

## Verified against DBC source (program 0.2.1, commit f552f20)

- `MAX_MIGRATION_FEE_PERCENTAGE = 99`; `create_config` takes `fee_claimer` as an unchecked account, so it can be a PDA.
- `withdraw_migration_fee`, `claim_trading_fee` and `partner_withdraw_surplus` require `fee_claimer` as signer.
- On DAMM v2 migration the partner position is minted to `config.fee_claimer` (the treasury).

## Devnet

Program `GBHTxatkmbAX5U7G65yXzDVAZjjjyW9btGZ1DNUHtcfh`. `scripts/demo.ts` runs two real raises
(happy path with a defended floor, and a rejected tranche that ends in redemptions); every
transaction is linked in [`docs/DEMO-devnet.md`](docs/DEMO-devnet.md).

## Web app

`app/` is a Vite + React front end that reuses the same client as the scripts (`scripts/lib/owncurve.ts`).
It lists every raise, draws the treasury as a vault split into tranches, shows the guarantees that
`bind_pool` checked on-chain, and lets anyone buy, object, settle and redeem. Connect a browser wallet
(Phantom, Solflare, Backpack…) or click **Use a test wallet** to try it on devnet without installing anything.

```
npm run app            # http://localhost:5173 (devnet; set VITE_RPC_URL in app/.env.local)
npm run e2e            # Chromium drives the whole lifecycle against LiteSVM with the real programs
```

## Agent Skill and CLI

[`skills/owncurve/SKILL.md`](skills/owncurve/SKILL.md) teaches any AI agent that supports Agent
Skills to launch and govern raises: read a raise, check the evidence of a pending tranche,
object on the holder's behalf, settle, redeem and defend the floor. It drives
`scripts/cli.ts`, which prints JSON and **simulates every write unless `--yes` is passed**.

```
npm run owncurve -- list
npm run owncurve -- show <config>           # includes "can": the actions this wallet can take now
npm run owncurve -- defend-floor <config>   # dry run; add --yes to send
```

## Build and test

```
anchor build --skip-lint --tools-version v1.52 --arch v0
npm ci
CLUSTER=local npx tsx --test tests/owncurve.test.ts   # 23 integration tests, real DBC + DAMM v2 binaries
npx tsx --test tests/cli.test.ts                      # the agent CLI end to end over JSON-RPC
npm run e2e                                           # Chromium drives the app, incl. floor defense
CLUSTER=local npx tsx scripts/f1.ts --migrate        # end-to-end flow in LiteSVM
npx tsx scripts/f1.ts --migrate                      # same flow on devnet
```

Local tests need `local/dynamic_bonding_curve.so` (built from DBC source at f552f20) and
`local/damm_v2.so` (DBC repo test fixture); `owncurve.sh` prepares both.

## Known limitations (MVP)

- Tokens sitting in the DBC/DAMM v2 pool count as circulating supply, so redemption pays them
  out only when someone buys them from the pool and redeems (an arbitrage floor, by design).
- Votes are locked tokens with no snapshot; flash-borrowed votes are possible but cost a round trip.

## License

MIT
OWNCURVE_EOF

mkdir -p 'programs/owncurve/src'
cat > 'programs/owncurve/src/lib.rs' <<'OWNCURVE_EOF'
//! OwnCurve — ownership coins on Meteora DBC.
//!
//! A raise is a normal Meteora Dynamic Bonding Curve launch whose config names this
//! program's treasury PDA as `fee_claimer` and `leftover_receiver`. At graduation the
//! DBC migration fee (up to 99% of the raise) lands in an on-chain treasury instead of
//! a wallet. The team receives it in milestone tranches; holders can lock tokens to
//! reject a tranche, and a successful rejection turns the treasury into a pro-rata
//! redemption pool (burn tokens -> receive quote).

use anchor_lang::prelude::*;
use anchor_spl::token_interface::{
    self, Burn, Mint, TokenAccount, TokenInterface, TransferChecked,
};
use dynamic_bonding_curve::{ConfigAccountLoader, PoolAccountLoader};

pub mod errors;
pub mod state;

use errors::OwnCurveError;
use state::*;

declare_id!("7e9AuP2h628b659tG771bUpMbWFS68Zxxx46cThisytb");

#[derive(AnchorSerialize, AnchorDeserialize, Clone)]
pub struct InitRaiseParams {
    pub min_treasury_pct: u8,
    pub tranche_bps: Vec<u16>,
    pub challenge_window: i64,
    pub reject_quorum_bps: u16,
    pub floor_reserve_bps: u16,
}

#[event]
pub struct TrancheRequested {
    pub raise: Pubkey,
    pub milestone: u8,
    pub amount: u64,
    pub evidence_uri: String,
    pub evidence_hash: [u8; 32],
    pub objections_close_at: i64,
}

#[event]
pub struct FloorDefended {
    pub raise: Pubkey,
    pub quote_spent: u64,
    pub tokens_bought_and_burned: u64,
    pub backing_per_token_before: u128, // quote base units per 1e9 base units, Q0
    pub backing_per_token_after: u128,
}

#[program]
pub mod owncurve {
    use super::*;

    /// Team registers a raise for a DBC config it is about to create (or has created).
    pub fn init_raise(ctx: Context<InitRaise>, params: InitRaiseParams) -> Result<()> {
        let n = params.tranche_bps.len();
        require!(n >= 1 && n <= MAX_MILESTONES, OwnCurveError::InvalidMilestones);
        let sum: u64 = params.tranche_bps.iter().map(|b| *b as u64).sum();
        require!(sum == BPS, OwnCurveError::InvalidMilestones);
        require!(
            params.min_treasury_pct >= MIN_TREASURY_PCT && params.min_treasury_pct <= 99,
            OwnCurveError::InvalidGovernance
        );
        require!(params.challenge_window >= MIN_CHALLENGE_WINDOW, OwnCurveError::InvalidGovernance);
        require!(
            params.reject_quorum_bps > 0 && params.reject_quorum_bps <= MAX_REJECT_QUORUM_BPS,
            OwnCurveError::InvalidGovernance
        );
        require!(params.floor_reserve_bps <= MAX_FLOOR_RESERVE_BPS, OwnCurveError::InvalidGovernance);

        let raise = &mut ctx.accounts.raise;
        raise.team = ctx.accounts.team.key();
        raise.dbc_config = ctx.accounts.dbc_config.key();
        raise.state = RaiseState::Pending;
        raise.min_treasury_pct = params.min_treasury_pct;
        raise.milestone_count = n as u8;
        for (i, bps) in params.tranche_bps.iter().enumerate() {
            raise.milestones[i] = Milestone { tranche_bps: *bps, status: MilestoneStatus::Locked, evidence_hash: [0; 32] };
        }
        for i in n..MAX_MILESTONES {
            raise.milestones[i] = Milestone { tranche_bps: 0, status: MilestoneStatus::Released, evidence_hash: [0; 32] };
        }
        raise.challenge_window = params.challenge_window;
        raise.reject_quorum_bps = params.reject_quorum_bps;
        raise.floor_reserve_bps = params.floor_reserve_bps;
        raise.bump = ctx.bumps.raise;
        raise.treasury_bump = ctx.bumps.treasury;
        Ok(())
    }

    /// Permissionless: reads the live DBC config + pool and proves the launch is
    /// treasury-safe before anyone should buy.
    pub fn bind_pool(ctx: Context<BindPool>) -> Result<()> {
        let raise = &mut ctx.accounts.raise;
        require!(raise.state == RaiseState::Pending, OwnCurveError::InvalidState);

        let config_info = ctx.accounts.dbc_config.to_account_info();
        let pool_info = ctx.accounts.dbc_pool.to_account_info();
        let treasury = ctx.accounts.treasury.key();

        let config_loader = ConfigAccountLoader::try_from(&config_info)
            .map_err(|_| error!(OwnCurveError::InvalidDbcAccount))?;
        let config = config_loader.load()?;
        require_keys_eq!(config.fee_claimer, treasury, OwnCurveError::FeeClaimerNotTreasury);
        require_keys_eq!(
            config.leftover_receiver,
            treasury,
            OwnCurveError::LeftoverReceiverNotTreasury
        );
        require!(
            config.creator_migration_fee_percentage == 0,
            OwnCurveError::CreatorMigrationFeeNotZero
        );
        require!(
            config.migration_fee_percentage >= raise.min_treasury_pct,
            OwnCurveError::TreasuryShareTooLow
        );
        // Anti-rug: the team must not be able to pull graduated liquidity out of DAMM v2.
        // (Partner LP is owned by the treasury PDA, which has no instruction to remove it.)
        require!(
            config.creator_liquidity_percentage == 0
                && config.creator_liquidity_vesting_info.vesting_percentage == 0,
            OwnCurveError::CreatorLpNotLocked
        );
        // Anti-rug: no infinite mint for the team (only possible on transfer-hook configs).
        require!(
            config.token_update_authority != DBC_CREATOR_MINT_AUTHORITY,
            OwnCurveError::CreatorMintAuthority
        );

        let pool_loader = PoolAccountLoader::try_from(&pool_info)
            .map_err(|_| error!(OwnCurveError::InvalidDbcAccount))?;
        let pool = pool_loader.load()?;
        require_keys_eq!(pool.config, raise.dbc_config, OwnCurveError::PoolConfigMismatch);
        require_keys_eq!(pool.creator, raise.team, OwnCurveError::PoolCreatorNotTeam);

        raise.dbc_pool = pool_info.key();
        raise.base_mint = pool.base_mint;
        raise.quote_mint = config.quote_mint;
        raise.state = RaiseState::Bonding;
        Ok(())
    }

    /// Permissionless: after graduation, pulls the partner migration fee into the
    /// treasury by CPI into DBC, signed by the treasury PDA (the config's fee_claimer).
    pub fn harvest(ctx: Context<Harvest>) -> Result<()> {
        require!(ctx.accounts.raise.state == RaiseState::Bonding, OwnCurveError::InvalidState);

        let before = ctx.accounts.treasury_quote.amount;
        let config_key = ctx.accounts.raise.dbc_config;
        let seeds: &[&[u8]] = &[TREASURY_SEED, config_key.as_ref(), &[ctx.accounts.raise.treasury_bump]];
        let signer = &[seeds];

        let cpi_accounts = dynamic_bonding_curve::cpi::accounts::WithdrawMigrationFeeCtx {
            pool_authority: ctx.accounts.dbc_pool_authority.to_account_info(),
            config: ctx.accounts.dbc_config.to_account_info(),
            virtual_pool: ctx.accounts.dbc_pool.to_account_info(),
            token_quote_account: ctx.accounts.treasury_quote.to_account_info(),
            quote_vault: ctx.accounts.dbc_quote_vault.to_account_info(),
            quote_mint: ctx.accounts.quote_mint.to_account_info(),
            sender: ctx.accounts.treasury.to_account_info(),
            token_quote_program: ctx.accounts.quote_token_program.to_account_info(),
            event_authority: ctx.accounts.dbc_event_authority.to_account_info(),
            program: ctx.accounts.dbc_program.to_account_info(),
        };
        dynamic_bonding_curve::cpi::withdraw_migration_fee(
            CpiContext::new_with_signer(ctx.accounts.dbc_program.key(), cpi_accounts, signer),
            0, // SenderFlag::Partner
        )?;

        ctx.accounts.treasury_quote.reload()?;
        let raised = ctx
            .accounts
            .treasury_quote
            .amount
            .checked_sub(before)
            .ok_or(OwnCurveError::MathOverflow)?;

        let raise = &mut ctx.accounts.raise;
        raise.funded_amount = raised;
        raise.state = RaiseState::Funded;
        Ok(())
    }

    /// Permissionless: pulls the partner share of DBC trading fees into the treasury.
    pub fn collect_trading_fees(ctx: Context<CollectTradingFees>) -> Result<()> {
        require!(ctx.accounts.raise.state != RaiseState::Pending, OwnCurveError::InvalidState);
        let before = ctx.accounts.treasury_quote.amount;
        let config_key = ctx.accounts.raise.dbc_config;
        let seeds: &[&[u8]] = &[TREASURY_SEED, config_key.as_ref(), &[ctx.accounts.raise.treasury_bump]];

        let cpi_accounts = dynamic_bonding_curve::cpi::accounts::ClaimTradingFeesCtx {
            pool_authority: ctx.accounts.dbc_pool_authority.to_account_info(),
            config: ctx.accounts.dbc_config.to_account_info(),
            pool: ctx.accounts.dbc_pool.to_account_info(),
            token_a_account: ctx.accounts.treasury_base.to_account_info(),
            token_b_account: ctx.accounts.treasury_quote.to_account_info(),
            base_vault: ctx.accounts.dbc_base_vault.to_account_info(),
            quote_vault: ctx.accounts.dbc_quote_vault.to_account_info(),
            base_mint: ctx.accounts.base_mint.to_account_info(),
            quote_mint: ctx.accounts.quote_mint.to_account_info(),
            fee_claimer: ctx.accounts.treasury.to_account_info(),
            token_base_program: ctx.accounts.base_token_program.to_account_info(),
            token_quote_program: ctx.accounts.quote_token_program.to_account_info(),
            event_authority: ctx.accounts.dbc_event_authority.to_account_info(),
            program: ctx.accounts.dbc_program.to_account_info(),
        };
        dynamic_bonding_curve::cpi::claim_trading_fee(
            CpiContext::new_with_signer(ctx.accounts.dbc_program.key(), cpi_accounts, &[seeds]),
            u64::MAX,
            u64::MAX,
        )?;
        add_collected(&mut ctx.accounts.raise, &mut ctx.accounts.treasury_quote, before)
    }

    /// Permissionless: if the last buy overshot the threshold, pulls the partner surplus.
    pub fn collect_surplus(ctx: Context<CollectSurplus>) -> Result<()> {
        require!(
            ctx.accounts.raise.state != RaiseState::Pending
                && ctx.accounts.raise.state != RaiseState::Bonding,
            OwnCurveError::InvalidState
        );
        let before = ctx.accounts.treasury_quote.amount;
        let config_key = ctx.accounts.raise.dbc_config;
        let seeds: &[&[u8]] = &[TREASURY_SEED, config_key.as_ref(), &[ctx.accounts.raise.treasury_bump]];

        let cpi_accounts = dynamic_bonding_curve::cpi::accounts::PartnerWithdrawSurplusCtx {
            pool_authority: ctx.accounts.dbc_pool_authority.to_account_info(),
            config: ctx.accounts.dbc_config.to_account_info(),
            virtual_pool: ctx.accounts.dbc_pool.to_account_info(),
            token_quote_account: ctx.accounts.treasury_quote.to_account_info(),
            quote_vault: ctx.accounts.dbc_quote_vault.to_account_info(),
            quote_mint: ctx.accounts.quote_mint.to_account_info(),
            fee_claimer: ctx.accounts.treasury.to_account_info(),
            token_quote_program: ctx.accounts.quote_token_program.to_account_info(),
            event_authority: ctx.accounts.dbc_event_authority.to_account_info(),
            program: ctx.accounts.dbc_program.to_account_info(),
        };
        dynamic_bonding_curve::cpi::partner_withdraw_surplus(CpiContext::new_with_signer(
            ctx.accounts.dbc_program.key(),
            cpi_accounts,
            &[seeds],
        ))?;
        add_collected(&mut ctx.accounts.raise, &mut ctx.accounts.treasury_quote, before)
    }

    /// Permissionless: after migration, claims the LP fees of the DAMM v2 position that DBC
    /// minted to the partner (= the treasury). The treasury earns trading fees forever.
    pub fn claim_lp_fees(ctx: Context<ClaimLpFees>) -> Result<()> {
        require!(
            ctx.accounts.raise.state != RaiseState::Pending
                && ctx.accounts.raise.state != RaiseState::Bonding,
            OwnCurveError::InvalidState
        );
        let before = ctx.accounts.treasury_quote.amount;
        let config_key = ctx.accounts.raise.dbc_config;
        let seeds: &[&[u8]] = &[TREASURY_SEED, config_key.as_ref(), &[ctx.accounts.raise.treasury_bump]];

        let cpi_accounts = damm_v2::cpi::accounts::ClaimPositionFee {
            pool_authority: ctx.accounts.damm_pool_authority.to_account_info(),
            pool: ctx.accounts.damm_pool.to_account_info(),
            position: ctx.accounts.position.to_account_info(),
            token_a_account: ctx.accounts.treasury_base.to_account_info(),
            token_b_account: ctx.accounts.treasury_quote.to_account_info(),
            token_a_vault: ctx.accounts.damm_base_vault.to_account_info(),
            token_b_vault: ctx.accounts.damm_quote_vault.to_account_info(),
            token_a_mint: ctx.accounts.base_mint.to_account_info(),
            token_b_mint: ctx.accounts.quote_mint.to_account_info(),
            position_nft_account: ctx.accounts.position_nft_account.to_account_info(),
            signer: ctx.accounts.treasury.to_account_info(),
            token_a_program: ctx.accounts.base_token_program.to_account_info(),
            token_b_program: ctx.accounts.quote_token_program.to_account_info(),
            event_authority: ctx.accounts.damm_event_authority.to_account_info(),
            program: ctx.accounts.damm_program.to_account_info(),
        };
        damm_v2::cpi::claim_position_fee(CpiContext::new_with_signer(
            ctx.accounts.damm_program.key(),
            cpi_accounts,
            &[seeds],
        ))?;
        add_collected(&mut ctx.accounts.raise, &mut ctx.accounts.treasury_quote, before)
    }

    /// Permissionless: when the token trades on DAMM v2 below what the treasury holds per
    /// token, spend floor reserve + collected fees buying it back, and burn what is bought.
    /// The program sets the minimum output itself, so the treasury can only ever pay a price at
    /// or below backing: every buyback raises the backing of the remaining tokens.
    pub fn defend_floor(ctx: Context<DefendFloor>, amount_in: u64) -> Result<()> {
        let raise = &ctx.accounts.raise;
        require!(
            raise.state == RaiseState::Funded || raise.state == RaiseState::Completed,
            OwnCurveError::InvalidState
        );
        require!(amount_in > 0, OwnCurveError::ZeroAmount);
        let budget = floor_budget(raise)?;
        require!(amount_in <= budget, OwnCurveError::FloorBudgetExceeded);

        let treasury_quote_before = ctx.accounts.treasury_quote.amount;
        let base_before = ctx.accounts.treasury_base.amount;
        let circulating = circulating_supply(ctx.accounts.base_mint.supply, base_before);
        require!(treasury_quote_before > 0 && circulating > 0, OwnCurveError::NothingToDefend);

        // Tokens the treasury must receive at least: amount_in at exactly backing price, rounded up.
        let min_out = ((amount_in as u128) * (circulating as u128))
            .checked_add(treasury_quote_before as u128 - 1)
            .ok_or(OwnCurveError::MathOverflow)?
            / (treasury_quote_before as u128);
        let min_out = u64::try_from(min_out).map_err(|_| error!(OwnCurveError::MathOverflow))?;

        let config_key = raise.dbc_config;
        let seeds: &[&[u8]] = &[TREASURY_SEED, config_key.as_ref(), &[raise.treasury_bump]];
        let cpi_accounts = damm_v2::cpi::accounts::Swap {
            pool_authority: ctx.accounts.damm_pool_authority.to_account_info(),
            pool: ctx.accounts.damm_pool.to_account_info(),
            input_token_account: ctx.accounts.treasury_quote.to_account_info(),
            output_token_account: ctx.accounts.treasury_base.to_account_info(),
            token_a_vault: ctx.accounts.damm_base_vault.to_account_info(),
            token_b_vault: ctx.accounts.damm_quote_vault.to_account_info(),
            token_a_mint: ctx.accounts.base_mint.to_account_info(),
            token_b_mint: ctx.accounts.quote_mint.to_account_info(),
            payer: ctx.accounts.treasury.to_account_info(),
            token_a_program: ctx.accounts.base_token_program.to_account_info(),
            token_b_program: ctx.accounts.quote_token_program.to_account_info(),
            referral_token_account: None,
            event_authority: ctx.accounts.damm_event_authority.to_account_info(),
            program: ctx.accounts.damm_program.to_account_info(),
        };
        damm_v2::cpi::swap(
            CpiContext::new_with_signer(ctx.accounts.damm_program.key(), cpi_accounts, &[seeds]),
            damm_v2::types::SwapParameters { amount_in, minimum_amount_out: min_out },
        )?;

        ctx.accounts.treasury_base.reload()?;
        ctx.accounts.treasury_quote.reload()?;
        let bought = ctx
            .accounts
            .treasury_base
            .amount
            .checked_sub(base_before)
            .ok_or(OwnCurveError::MathOverflow)?;
        let spent = treasury_quote_before
            .checked_sub(ctx.accounts.treasury_quote.amount)
            .ok_or(OwnCurveError::MathOverflow)?;
        require!(bought >= min_out, OwnCurveError::NothingToDefend);

        token_interface::burn(
            CpiContext::new_with_signer(
                ctx.accounts.base_token_program.key(),
                Burn {
                    mint: ctx.accounts.base_mint.to_account_info(),
                    from: ctx.accounts.treasury_base.to_account_info(),
                    authority: ctx.accounts.treasury.to_account_info(),
                },
                &[seeds],
            ),
            bought,
        )?;

        let backing_before = backing_per_token(treasury_quote_before, circulating);
        let backing_after = backing_per_token(ctx.accounts.treasury_quote.amount, circulating - bought);
        let raise_key = ctx.accounts.raise.key();
        let raise = &mut ctx.accounts.raise;
        raise.floor_spent = raise.floor_spent.checked_add(spent).ok_or(OwnCurveError::MathOverflow)?;
        raise.tokens_burned = raise.tokens_burned.checked_add(bought).ok_or(OwnCurveError::MathOverflow)?;
        emit!(FloorDefended {
            raise: raise_key,
            quote_spent: spent,
            tokens_bought_and_burned: bought,
            backing_per_token_before: backing_before,
            backing_per_token_after: backing_after,
        });
        Ok(())
    }

    /// Team requests the next milestone tranche, committing to evidence of the delivered work
    /// (a link plus a hash); opens the challenge window.
    pub fn propose_release(
        ctx: Context<TeamAction>,
        evidence_uri: String,
        evidence_hash: [u8; 32],
    ) -> Result<()> {
        require!(
            !evidence_uri.trim().is_empty() && evidence_uri.len() <= MAX_EVIDENCE_URI,
            OwnCurveError::InvalidEvidence
        );
        let raise_key = ctx.accounts.raise.key();
        let raise = &mut ctx.accounts.raise;
        require!(raise.state == RaiseState::Funded, OwnCurveError::InvalidState);
        require!(
            !raise.milestones.iter().any(|m| m.status == MilestoneStatus::Proposed),
            OwnCurveError::ProposalActive
        );
        let next = raise
            .milestones
            .iter()
            .position(|m| m.status == MilestoneStatus::Locked)
            .ok_or(OwnCurveError::MilestoneOutOfOrder)?;

        raise.milestones[next].status = MilestoneStatus::Proposed;
        raise.milestones[next].evidence_hash = evidence_hash;
        raise.proposal_milestone = next as u8;
        raise.proposal_reject_weight = 0;
        raise.proposal_evidence_uri = evidence_uri.clone();
        raise.proposal_ends_at = Clock::get()?
            .unix_timestamp
            .checked_add(raise.challenge_window)
            .ok_or(OwnCurveError::MathOverflow)?;
        emit!(TrancheRequested {
            raise: raise_key,
            milestone: next as u8,
            amount: tranche_amount(raise, next),
            evidence_uri,
            evidence_hash,
            objections_close_at: raise.proposal_ends_at,
        });
        Ok(())
    }

    /// Holder locks base tokens as a "reject" vote on the active proposal.
    pub fn reject(ctx: Context<Reject>, amount: u64) -> Result<()> {
        require!(amount > 0, OwnCurveError::ZeroAmount);
        let raise = &ctx.accounts.raise;
        require!(raise.state == RaiseState::Funded, OwnCurveError::InvalidState);
        require!(
            raise.milestones[raise.proposal_milestone as usize].status == MilestoneStatus::Proposed,
            OwnCurveError::NoActiveProposal
        );
        require!(
            Clock::get()?.unix_timestamp < raise.proposal_ends_at,
            OwnCurveError::ChallengeWindowClosed
        );

        token_interface::transfer_checked(
            CpiContext::new(
                ctx.accounts.base_token_program.key(),
                TransferChecked {
                    from: ctx.accounts.voter_base.to_account_info(),
                    mint: ctx.accounts.base_mint.to_account_info(),
                    to: ctx.accounts.escrow_base.to_account_info(),
                    authority: ctx.accounts.voter.to_account_info(),
                },
            ),
            amount,
            ctx.accounts.base_mint.decimals,
        )?;

        let vote = &mut ctx.accounts.vote;
        if vote.amount == 0 {
            vote.raise = raise.key();
            vote.voter = ctx.accounts.voter.key();
            vote.proposal_nonce = raise.proposal_nonce;
            vote.bump = ctx.bumps.vote;
        }
        vote.amount = vote.amount.checked_add(amount).ok_or(OwnCurveError::MathOverflow)?;

        let raise = &mut ctx.accounts.raise;
        raise.proposal_reject_weight = raise
            .proposal_reject_weight
            .checked_add(amount)
            .ok_or(OwnCurveError::MathOverflow)?;
        Ok(())
    }

    /// Permissionless after the window: releases the tranche, or flips the raise into
    /// liquidation if the reject quorum was met.
    pub fn finalize(ctx: Context<Finalize>) -> Result<()> {
        let raise = &ctx.accounts.raise;
        require!(raise.state == RaiseState::Funded, OwnCurveError::InvalidState);
        let idx = raise.proposal_milestone as usize;
        require!(
            raise.milestones[idx].status == MilestoneStatus::Proposed,
            OwnCurveError::NoActiveProposal
        );
        require!(
            Clock::get()?.unix_timestamp >= raise.proposal_ends_at,
            OwnCurveError::ChallengeWindowOpen
        );

        let circulating = circulating_supply(
            ctx.accounts.base_mint.supply,
            ctx.accounts.treasury_base.amount,
        );
        let rejected = (raise.proposal_reject_weight as u128) * (BPS as u128)
            >= (raise.reject_quorum_bps as u128) * (circulating as u128);

        if rejected {
            let raise = &mut ctx.accounts.raise;
            raise.milestones[idx].status = MilestoneStatus::Locked;
            raise.state = RaiseState::Liquidating;
            raise.proposal_nonce += 1;
            return Ok(());
        }

        let is_last = (idx + 1) as u8 == raise.milestone_count;
        let tranche = tranche_amount(raise, idx);

        let config_key = raise.dbc_config;
        let seeds: &[&[u8]] = &[TREASURY_SEED, config_key.as_ref(), &[raise.treasury_bump]];
        token_interface::transfer_checked(
            CpiContext::new_with_signer(
                ctx.accounts.quote_token_program.key(),
                TransferChecked {
                    from: ctx.accounts.treasury_quote.to_account_info(),
                    mint: ctx.accounts.quote_mint.to_account_info(),
                    to: ctx.accounts.team_quote.to_account_info(),
                    authority: ctx.accounts.treasury.to_account_info(),
                },
                &[seeds],
            ),
            tranche,
            ctx.accounts.quote_mint.decimals,
        )?;

        let raise = &mut ctx.accounts.raise;
        raise.milestones[idx].status = MilestoneStatus::Released;
        raise.released_amount = raise
            .released_amount
            .checked_add(tranche)
            .ok_or(OwnCurveError::MathOverflow)?;
        raise.proposal_nonce += 1;
        if is_last {
            raise.state = RaiseState::Completed;
        }
        Ok(())
    }

    /// Returns a voter's locked tokens once their proposal has been finalized.
    pub fn withdraw_vote(ctx: Context<WithdrawVote>) -> Result<()> {
        let raise = &ctx.accounts.raise;
        require!(
            ctx.accounts.vote.proposal_nonce < raise.proposal_nonce,
            OwnCurveError::VoteStillLocked
        );
        let raise_key = raise.key();
        let bump = ctx.bumps.escrow;
        let seeds: &[&[u8]] = &[ESCROW_SEED, raise_key.as_ref(), &[bump]];
        token_interface::transfer_checked(
            CpiContext::new_with_signer(
                ctx.accounts.base_token_program.key(),
                TransferChecked {
                    from: ctx.accounts.escrow_base.to_account_info(),
                    mint: ctx.accounts.base_mint.to_account_info(),
                    to: ctx.accounts.voter_base.to_account_info(),
                    authority: ctx.accounts.escrow.to_account_info(),
                },
                &[seeds],
            ),
            ctx.accounts.vote.amount,
            ctx.accounts.base_mint.decimals,
        )?;
        Ok(())
    }

    /// In liquidation: burn base tokens, receive a pro-rata share of the treasury.
    pub fn redeem(ctx: Context<Redeem>, amount: u64) -> Result<()> {
        require!(amount > 0, OwnCurveError::ZeroAmount);
        let raise = &ctx.accounts.raise;
        require!(raise.state == RaiseState::Liquidating, OwnCurveError::InvalidState);

        let circulating = circulating_supply(
            ctx.accounts.base_mint.supply,
            ctx.accounts.treasury_base.amount,
        );
        require!(circulating > 0, OwnCurveError::MathOverflow);
        let payout = ((amount as u128) * (ctx.accounts.treasury_quote.amount as u128)
            / (circulating as u128)) as u64;

        token_interface::burn(
            CpiContext::new(
                ctx.accounts.base_token_program.key(),
                Burn {
                    mint: ctx.accounts.base_mint.to_account_info(),
                    from: ctx.accounts.holder_base.to_account_info(),
                    authority: ctx.accounts.holder.to_account_info(),
                },
            ),
            amount,
        )?;

        let config_key = raise.dbc_config;
        let seeds: &[&[u8]] = &[TREASURY_SEED, config_key.as_ref(), &[raise.treasury_bump]];
        token_interface::transfer_checked(
            CpiContext::new_with_signer(
                ctx.accounts.quote_token_program.key(),
                TransferChecked {
                    from: ctx.accounts.treasury_quote.to_account_info(),
                    mint: ctx.accounts.quote_mint.to_account_info(),
                    to: ctx.accounts.holder_quote.to_account_info(),
                    authority: ctx.accounts.treasury.to_account_info(),
                },
                &[seeds],
            ),
            payout,
            ctx.accounts.quote_mint.decimals,
        )?;
        Ok(())
    }
}

/// Quote payable to the team for milestone `idx`: tranches split `funded − floor reserve`;
/// the last one takes the rounding remainder so the payable amount is paid out exactly.
fn tranche_amount(raise: &Raise, idx: usize) -> u64 {
    let payable = payable_amount(raise);
    if (idx + 1) as u8 == raise.milestone_count {
        payable.saturating_sub(raise.released_amount)
    } else {
        ((payable as u128) * (raise.milestones[idx].tranche_bps as u128) / (BPS as u128)) as u64
    }
}

fn payable_amount(raise: &Raise) -> u64 {
    let reserve = (raise.funded_amount as u128) * (raise.floor_reserve_bps as u128) / (BPS as u128);
    raise.funded_amount.saturating_sub(reserve as u64)
}

/// What `defend_floor` may still spend: the floor reserve plus collected fees, minus what was spent.
fn floor_budget(raise: &Raise) -> Result<u64> {
    let reserve = raise.funded_amount - payable_amount(raise);
    Ok(reserve
        .checked_add(raise.fees_collected)
        .ok_or(OwnCurveError::MathOverflow)?
        .saturating_sub(raise.floor_spent))
}

/// Treasury quote per 1e9 base units (for events and UIs).
fn backing_per_token(treasury_quote: u64, circulating: u64) -> u128 {
    if circulating == 0 {
        return 0;
    }
    (treasury_quote as u128) * 1_000_000_000 / (circulating as u128)
}

/// Adds the quote that just landed in the treasury to `fees_collected`.
fn add_collected<'info>(
    raise: &mut Account<'info, Raise>,
    treasury_quote: &mut InterfaceAccount<'info, TokenAccount>,
    before: u64,
) -> Result<()> {
    treasury_quote.reload()?;
    let delta = treasury_quote.amount.checked_sub(before).ok_or(OwnCurveError::MathOverflow)?;
    raise.fees_collected = raise.fees_collected.checked_add(delta).ok_or(OwnCurveError::MathOverflow)?;
    Ok(())
}

/// Supply that has a claim on the treasury: total minus tokens the treasury itself holds
/// (DBC leftover). Tokens inside the DAMM v2 pool still count — documented MVP trade-off.
fn circulating_supply(total: u64, treasury_held: u64) -> u64 {
    total.saturating_sub(treasury_held)
}

// ---------------------------------------------------------------------------
// Accounts
// ---------------------------------------------------------------------------

#[derive(Accounts)]
pub struct InitRaise<'info> {
    #[account(mut)]
    pub team: Signer<'info>,
    /// CHECK: the DBC config this raise will bind to (may not exist yet; validated in bind_pool).
    pub dbc_config: UncheckedAccount<'info>,
    #[account(
        init,
        payer = team,
        space = 8 + Raise::INIT_SPACE,
        seeds = [RAISE_SEED, dbc_config.key().as_ref()],
        bump
    )]
    pub raise: Box<Account<'info, Raise>>,
    /// CHECK: PDA only; set as fee_claimer + leftover_receiver on the DBC config.
    #[account(seeds = [TREASURY_SEED, dbc_config.key().as_ref()], bump)]
    pub treasury: UncheckedAccount<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct BindPool<'info> {
    #[account(mut, seeds = [RAISE_SEED, raise.dbc_config.as_ref()], bump = raise.bump)]
    pub raise: Box<Account<'info, Raise>>,
    /// CHECK: PDA
    #[account(seeds = [TREASURY_SEED, raise.dbc_config.as_ref()], bump = raise.treasury_bump)]
    pub treasury: UncheckedAccount<'info>,
    /// CHECK: owner + discriminator checked by ConfigAccountLoader
    #[account(address = raise.dbc_config)]
    pub dbc_config: UncheckedAccount<'info>,
    /// CHECK: owner + discriminator checked by PoolAccountLoader
    pub dbc_pool: UncheckedAccount<'info>,
}

#[derive(Accounts)]
pub struct Harvest<'info> {
    #[account(mut, seeds = [RAISE_SEED, raise.dbc_config.as_ref()], bump = raise.bump)]
    pub raise: Box<Account<'info, Raise>>,
    /// CHECK: PDA signer for the DBC CPI
    #[account(seeds = [TREASURY_SEED, raise.dbc_config.as_ref()], bump = raise.treasury_bump)]
    pub treasury: UncheckedAccount<'info>,
    #[account(
        mut,
        token::mint = quote_mint,
        token::authority = treasury,
        token::token_program = quote_token_program
    )]
    pub treasury_quote: Box<InterfaceAccount<'info, TokenAccount>>,
    #[account(address = raise.quote_mint)]
    pub quote_mint: Box<InterfaceAccount<'info, Mint>>,
    /// CHECK: validated by DBC
    pub dbc_pool_authority: UncheckedAccount<'info>,
    /// CHECK: validated by DBC
    #[account(address = raise.dbc_config)]
    pub dbc_config: UncheckedAccount<'info>,
    /// CHECK: validated by DBC
    #[account(mut, address = raise.dbc_pool)]
    pub dbc_pool: UncheckedAccount<'info>,
    /// CHECK: validated by DBC
    #[account(mut)]
    pub dbc_quote_vault: UncheckedAccount<'info>,
    /// CHECK: validated by DBC
    pub dbc_event_authority: UncheckedAccount<'info>,
    /// CHECK: address-checked
    #[account(address = dynamic_bonding_curve::ID)]
    pub dbc_program: UncheckedAccount<'info>,
    pub quote_token_program: Interface<'info, TokenInterface>,
}

/// Treasury token accounts + mints shared by every fee-collecting instruction.
/// Destinations are pinned to the treasury, so nobody can redirect what is collected.
#[derive(Accounts)]
pub struct CollectTradingFees<'info> {
    #[account(mut, seeds = [RAISE_SEED, raise.dbc_config.as_ref()], bump = raise.bump)]
    pub raise: Box<Account<'info, Raise>>,
    /// CHECK: PDA signer for the DBC CPI
    #[account(seeds = [TREASURY_SEED, raise.dbc_config.as_ref()], bump = raise.treasury_bump)]
    pub treasury: UncheckedAccount<'info>,
    #[account(mut, token::mint = base_mint, token::authority = treasury, token::token_program = base_token_program)]
    pub treasury_base: Box<InterfaceAccount<'info, TokenAccount>>,
    #[account(mut, token::mint = quote_mint, token::authority = treasury, token::token_program = quote_token_program)]
    pub treasury_quote: Box<InterfaceAccount<'info, TokenAccount>>,
    #[account(address = raise.base_mint)]
    pub base_mint: Box<InterfaceAccount<'info, Mint>>,
    #[account(address = raise.quote_mint)]
    pub quote_mint: Box<InterfaceAccount<'info, Mint>>,
    /// CHECK: validated by DBC
    pub dbc_pool_authority: UncheckedAccount<'info>,
    /// CHECK: validated by DBC
    #[account(address = raise.dbc_config)]
    pub dbc_config: UncheckedAccount<'info>,
    /// CHECK: validated by DBC
    #[account(mut, address = raise.dbc_pool)]
    pub dbc_pool: UncheckedAccount<'info>,
    /// CHECK: validated by DBC
    #[account(mut)]
    pub dbc_base_vault: UncheckedAccount<'info>,
    /// CHECK: validated by DBC
    #[account(mut)]
    pub dbc_quote_vault: UncheckedAccount<'info>,
    /// CHECK: validated by DBC
    pub dbc_event_authority: UncheckedAccount<'info>,
    /// CHECK: address-checked
    #[account(address = dynamic_bonding_curve::ID)]
    pub dbc_program: UncheckedAccount<'info>,
    pub base_token_program: Interface<'info, TokenInterface>,
    pub quote_token_program: Interface<'info, TokenInterface>,
}

#[derive(Accounts)]
pub struct CollectSurplus<'info> {
    #[account(mut, seeds = [RAISE_SEED, raise.dbc_config.as_ref()], bump = raise.bump)]
    pub raise: Box<Account<'info, Raise>>,
    /// CHECK: PDA signer for the DBC CPI
    #[account(seeds = [TREASURY_SEED, raise.dbc_config.as_ref()], bump = raise.treasury_bump)]
    pub treasury: UncheckedAccount<'info>,
    #[account(mut, token::mint = quote_mint, token::authority = treasury, token::token_program = quote_token_program)]
    pub treasury_quote: Box<InterfaceAccount<'info, TokenAccount>>,
    #[account(address = raise.quote_mint)]
    pub quote_mint: Box<InterfaceAccount<'info, Mint>>,
    /// CHECK: validated by DBC
    pub dbc_pool_authority: UncheckedAccount<'info>,
    /// CHECK: validated by DBC
    #[account(address = raise.dbc_config)]
    pub dbc_config: UncheckedAccount<'info>,
    /// CHECK: validated by DBC
    #[account(mut, address = raise.dbc_pool)]
    pub dbc_pool: UncheckedAccount<'info>,
    /// CHECK: validated by DBC
    #[account(mut)]
    pub dbc_quote_vault: UncheckedAccount<'info>,
    /// CHECK: validated by DBC
    pub dbc_event_authority: UncheckedAccount<'info>,
    /// CHECK: address-checked
    #[account(address = dynamic_bonding_curve::ID)]
    pub dbc_program: UncheckedAccount<'info>,
    pub quote_token_program: Interface<'info, TokenInterface>,
}

#[derive(Accounts)]
pub struct ClaimLpFees<'info> {
    #[account(mut, seeds = [RAISE_SEED, raise.dbc_config.as_ref()], bump = raise.bump)]
    pub raise: Box<Account<'info, Raise>>,
    /// CHECK: PDA signer (owner of the DAMM v2 position NFT)
    #[account(seeds = [TREASURY_SEED, raise.dbc_config.as_ref()], bump = raise.treasury_bump)]
    pub treasury: UncheckedAccount<'info>,
    #[account(mut, token::mint = base_mint, token::authority = treasury, token::token_program = base_token_program)]
    pub treasury_base: Box<InterfaceAccount<'info, TokenAccount>>,
    #[account(mut, token::mint = quote_mint, token::authority = treasury, token::token_program = quote_token_program)]
    pub treasury_quote: Box<InterfaceAccount<'info, TokenAccount>>,
    #[account(address = raise.base_mint)]
    pub base_mint: Box<InterfaceAccount<'info, Mint>>,
    #[account(address = raise.quote_mint)]
    pub quote_mint: Box<InterfaceAccount<'info, Mint>>,
    /// CHECK: validated by DAMM v2
    pub damm_pool_authority: UncheckedAccount<'info>,
    /// CHECK: validated by DAMM v2 (vaults and mints must match the pool)
    pub damm_pool: UncheckedAccount<'info>,
    /// CHECK: validated by DAMM v2
    #[account(mut)]
    pub position: UncheckedAccount<'info>,
    /// CHECK: validated by DAMM v2
    #[account(mut)]
    pub damm_base_vault: UncheckedAccount<'info>,
    /// CHECK: validated by DAMM v2
    #[account(mut)]
    pub damm_quote_vault: UncheckedAccount<'info>,
    /// CHECK: validated by DAMM v2 (must be held by the treasury)
    pub position_nft_account: UncheckedAccount<'info>,
    /// CHECK: validated by DAMM v2
    pub damm_event_authority: UncheckedAccount<'info>,
    /// CHECK: address-checked
    #[account(address = damm_v2::ID)]
    pub damm_program: UncheckedAccount<'info>,
    pub base_token_program: Interface<'info, TokenInterface>,
    pub quote_token_program: Interface<'info, TokenInterface>,
}

#[derive(Accounts)]
pub struct DefendFloor<'info> {
    #[account(mut, seeds = [RAISE_SEED, raise.dbc_config.as_ref()], bump = raise.bump)]
    pub raise: Box<Account<'info, Raise>>,
    /// CHECK: PDA signer (owner of the treasury token accounts)
    #[account(seeds = [TREASURY_SEED, raise.dbc_config.as_ref()], bump = raise.treasury_bump)]
    pub treasury: UncheckedAccount<'info>,
    #[account(mut, token::mint = base_mint, token::authority = treasury, token::token_program = base_token_program)]
    pub treasury_base: Box<InterfaceAccount<'info, TokenAccount>>,
    #[account(mut, token::mint = quote_mint, token::authority = treasury, token::token_program = quote_token_program)]
    pub treasury_quote: Box<InterfaceAccount<'info, TokenAccount>>,
    #[account(mut, address = raise.base_mint)]
    pub base_mint: Box<InterfaceAccount<'info, Mint>>,
    #[account(address = raise.quote_mint)]
    pub quote_mint: Box<InterfaceAccount<'info, Mint>>,
    /// CHECK: validated by DAMM v2
    pub damm_pool_authority: UncheckedAccount<'info>,
    /// CHECK: validated by DAMM v2 (its vaults and mints must match); the program-set
    /// minimum output protects the treasury whichever pool is passed.
    #[account(mut)]
    pub damm_pool: UncheckedAccount<'info>,
    /// CHECK: validated by DAMM v2
    #[account(mut)]
    pub damm_base_vault: UncheckedAccount<'info>,
    /// CHECK: validated by DAMM v2
    #[account(mut)]
    pub damm_quote_vault: UncheckedAccount<'info>,
    /// CHECK: validated by DAMM v2
    pub damm_event_authority: UncheckedAccount<'info>,
    /// CHECK: address-checked
    #[account(address = damm_v2::ID)]
    pub damm_program: UncheckedAccount<'info>,
    pub base_token_program: Interface<'info, TokenInterface>,
    pub quote_token_program: Interface<'info, TokenInterface>,
}

#[derive(Accounts)]
pub struct TeamAction<'info> {
    #[account(address = raise.team @ OwnCurveError::NotTeam)]
    pub team: Signer<'info>,
    #[account(mut, seeds = [RAISE_SEED, raise.dbc_config.as_ref()], bump = raise.bump)]
    pub raise: Box<Account<'info, Raise>>,
}

#[derive(Accounts)]
pub struct Reject<'info> {
    #[account(mut)]
    pub voter: Signer<'info>,
    #[account(mut, seeds = [RAISE_SEED, raise.dbc_config.as_ref()], bump = raise.bump)]
    pub raise: Box<Account<'info, Raise>>,
    #[account(
        init_if_needed,
        payer = voter,
        space = 8 + VoteRecord::INIT_SPACE,
        seeds = [VOTE_SEED, raise.key().as_ref(), voter.key().as_ref(), &raise.proposal_nonce.to_le_bytes()],
        bump
    )]
    pub vote: Account<'info, VoteRecord>,
    /// CHECK: PDA authority of the vote escrow
    #[account(seeds = [ESCROW_SEED, raise.key().as_ref()], bump)]
    pub escrow: UncheckedAccount<'info>,
    #[account(mut, token::mint = base_mint, token::authority = escrow, token::token_program = base_token_program)]
    pub escrow_base: Box<InterfaceAccount<'info, TokenAccount>>,
    #[account(mut, token::mint = base_mint, token::authority = voter, token::token_program = base_token_program)]
    pub voter_base: Box<InterfaceAccount<'info, TokenAccount>>,
    #[account(address = raise.base_mint)]
    pub base_mint: Box<InterfaceAccount<'info, Mint>>,
    pub base_token_program: Interface<'info, TokenInterface>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct Finalize<'info> {
    #[account(mut, seeds = [RAISE_SEED, raise.dbc_config.as_ref()], bump = raise.bump)]
    pub raise: Box<Account<'info, Raise>>,
    /// CHECK: PDA signer
    #[account(seeds = [TREASURY_SEED, raise.dbc_config.as_ref()], bump = raise.treasury_bump)]
    pub treasury: UncheckedAccount<'info>,
    #[account(mut, token::mint = quote_mint, token::authority = treasury, token::token_program = quote_token_program)]
    pub treasury_quote: Box<InterfaceAccount<'info, TokenAccount>>,
    #[account(token::mint = base_mint, token::authority = treasury)]
    pub treasury_base: Box<InterfaceAccount<'info, TokenAccount>>,
    #[account(mut, token::mint = quote_mint, token::authority = raise.team, token::token_program = quote_token_program)]
    pub team_quote: Box<InterfaceAccount<'info, TokenAccount>>,
    #[account(address = raise.quote_mint)]
    pub quote_mint: Box<InterfaceAccount<'info, Mint>>,
    #[account(address = raise.base_mint)]
    pub base_mint: Box<InterfaceAccount<'info, Mint>>,
    pub quote_token_program: Interface<'info, TokenInterface>,
}

#[derive(Accounts)]
pub struct WithdrawVote<'info> {
    #[account(mut)]
    pub voter: Signer<'info>,
    #[account(seeds = [RAISE_SEED, raise.dbc_config.as_ref()], bump = raise.bump)]
    pub raise: Box<Account<'info, Raise>>,
    #[account(
        mut,
        close = voter,
        has_one = voter,
        seeds = [VOTE_SEED, raise.key().as_ref(), voter.key().as_ref(), &vote.proposal_nonce.to_le_bytes()],
        bump = vote.bump
    )]
    pub vote: Account<'info, VoteRecord>,
    /// CHECK: PDA authority of the vote escrow
    #[account(seeds = [ESCROW_SEED, raise.key().as_ref()], bump)]
    pub escrow: UncheckedAccount<'info>,
    #[account(mut, token::mint = base_mint, token::authority = escrow, token::token_program = base_token_program)]
    pub escrow_base: Box<InterfaceAccount<'info, TokenAccount>>,
    #[account(mut, token::mint = base_mint, token::authority = voter, token::token_program = base_token_program)]
    pub voter_base: Box<InterfaceAccount<'info, TokenAccount>>,
    #[account(address = raise.base_mint)]
    pub base_mint: Box<InterfaceAccount<'info, Mint>>,
    pub base_token_program: Interface<'info, TokenInterface>,
}

#[derive(Accounts)]
pub struct Redeem<'info> {
    pub holder: Signer<'info>,
    #[account(seeds = [RAISE_SEED, raise.dbc_config.as_ref()], bump = raise.bump)]
    pub raise: Box<Account<'info, Raise>>,
    /// CHECK: PDA signer
    #[account(seeds = [TREASURY_SEED, raise.dbc_config.as_ref()], bump = raise.treasury_bump)]
    pub treasury: UncheckedAccount<'info>,
    #[account(mut, token::mint = quote_mint, token::authority = treasury, token::token_program = quote_token_program)]
    pub treasury_quote: Box<InterfaceAccount<'info, TokenAccount>>,
    #[account(token::mint = base_mint, token::authority = treasury, token::token_program = base_token_program)]
    pub treasury_base: Box<InterfaceAccount<'info, TokenAccount>>,
    #[account(mut, token::mint = base_mint, token::authority = holder, token::token_program = base_token_program)]
    pub holder_base: Box<InterfaceAccount<'info, TokenAccount>>,
    #[account(mut, token::mint = quote_mint, token::authority = holder, token::token_program = quote_token_program)]
    pub holder_quote: Box<InterfaceAccount<'info, TokenAccount>>,
    #[account(mut, address = raise.base_mint)]
    pub base_mint: Box<InterfaceAccount<'info, Mint>>,
    #[account(address = raise.quote_mint)]
    pub quote_mint: Box<InterfaceAccount<'info, Mint>>,
    pub base_token_program: Interface<'info, TokenInterface>,
    pub quote_token_program: Interface<'info, TokenInterface>,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn raise_with(funded: u64, floor_bps: u16, tranches: &[u16]) -> Raise {
        let mut milestones = [Milestone { tranche_bps: 0, status: MilestoneStatus::Released, evidence_hash: [0; 32] }; MAX_MILESTONES];
        for (i, b) in tranches.iter().enumerate() {
            milestones[i] = Milestone { tranche_bps: *b, status: MilestoneStatus::Locked, evidence_hash: [0; 32] };
        }
        Raise {
            team: Pubkey::default(),
            dbc_config: Pubkey::default(),
            dbc_pool: Pubkey::default(),
            base_mint: Pubkey::default(),
            quote_mint: Pubkey::default(),
            state: RaiseState::Funded,
            min_treasury_pct: 80,
            funded_amount: funded,
            released_amount: 0,
            fees_collected: 0,
            floor_reserve_bps: floor_bps,
            floor_spent: 0,
            tokens_burned: 0,
            milestones,
            milestone_count: tranches.len() as u8,
            challenge_window: 60,
            reject_quorum_bps: 1000,
            proposal_nonce: 0,
            proposal_milestone: 0,
            proposal_ends_at: 0,
            proposal_reject_weight: 0,
            proposal_evidence_uri: String::new(),
            bump: 0,
            treasury_bump: 0,
        }
    }

    #[test]
    fn tranches_pay_exactly_the_payable_amount() {
        for (funded, floor) in [(400_000_000u64, 0u16), (400_000_001, 2000), (999_999_999, 5000), (7, 3333)] {
            let mut r = raise_with(funded, floor, &[3000, 3000, 4000]);
            for i in 0..3 {
                let t = tranche_amount(&r, i);
                r.released_amount += t;
            }
            assert_eq!(r.released_amount, payable_amount(&r));
            assert_eq!(payable_amount(&r) + (funded - payable_amount(&r)), funded);
        }
    }

    #[test]
    fn floor_budget_is_reserve_plus_fees_minus_spent() {
        let mut r = raise_with(400_000_000, 2000, &[10_000]);
        assert_eq!(floor_budget(&r).unwrap(), 80_000_000);
        r.fees_collected = 5_000_000;
        r.floor_spent = 30_000_000;
        assert_eq!(floor_budget(&r).unwrap(), 55_000_000);
        r.floor_spent = 100_000_000;
        assert_eq!(floor_budget(&r).unwrap(), 0);
    }

    #[test]
    fn circulating_excludes_treasury_held() {
        assert_eq!(circulating_supply(1_000, 200), 800);
        assert_eq!(circulating_supply(100, 500), 0);
    }
}
OWNCURVE_EOF

mkdir -p 'programs/owncurve/src'
cat > 'programs/owncurve/src/state.rs' <<'OWNCURVE_EOF'
use anchor_lang::prelude::*;

pub const RAISE_SEED: &[u8] = b"raise";
pub const TREASURY_SEED: &[u8] = b"treasury";
pub const ESCROW_SEED: &[u8] = b"escrow";
pub const VOTE_SEED: &[u8] = b"vote";

pub const MAX_MILESTONES: usize = 5;
/// Governance guard-rails a team cannot opt out of.
pub const MIN_TREASURY_PCT: u8 = 50; // at least half of the raise backs the token
pub const MIN_CHALLENGE_WINDOW: i64 = 60; // seconds holders always get to react
pub const MAX_REJECT_QUORUM_BPS: u16 = 3_000; // blocking a tranche never needs more than 30%
/// DBC `TokenAuthorityOption::CreatorUpdateAndMintAuthority`.
pub const DBC_CREATOR_MINT_AUTHORITY: u8 = 3;
pub const BPS: u64 = 10_000;
/// Share of the raise a team can set aside as a permanent floor reserve (never paid out).
pub const MAX_FLOOR_RESERVE_BPS: u16 = 5_000;
/// Max length of the evidence link attached to a tranche request.
pub const MAX_EVIDENCE_URI: usize = 160;

/// Lifecycle of a raise.
#[derive(AnchorSerialize, AnchorDeserialize, Clone, Copy, PartialEq, Eq, Debug, InitSpace)]
pub enum RaiseState {
    /// Raise created, DBC config/pool not yet bound and validated.
    Pending,
    /// Pool bound and validated; token is trading on the DBC curve.
    Bonding,
    /// Curve graduated and the migration fee was harvested into the treasury.
    Funded,
    /// Holders rejected a tranche: treasury is redeemable pro rata by burning tokens.
    Liquidating,
    /// Every milestone tranche was released to the team.
    Completed,
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Copy, PartialEq, Eq, Debug, InitSpace)]
pub enum MilestoneStatus {
    Locked,
    Proposed,
    Released,
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Copy, Debug, InitSpace)]
pub struct Milestone {
    /// Share of the payable treasury (funded minus floor reserve) released at this milestone, in bps.
    pub tranche_bps: u16,
    pub status: MilestoneStatus,
    /// SHA-256 the team committed to when requesting this tranche (e.g. a release or commit hash).
    pub evidence_hash: [u8; 32],
}

/// One raise = one DBC config = one DBC pool.
/// The treasury PDA (seeds: ["treasury", dbc_config]) is set as the DBC config's
/// `fee_claimer` and `leftover_receiver`, so every partner-side flow of the launch
/// (migration fee, partner trading fees, surplus, leftover, and — on transfer-hook
/// configs — the mint authority) can only be moved by this program.
#[account]
#[derive(InitSpace)]
pub struct Raise {
    pub team: Pubkey,
    pub dbc_config: Pubkey,
    pub dbc_pool: Pubkey,
    pub base_mint: Pubkey,
    pub quote_mint: Pubkey,
    pub state: RaiseState,

    /// Minimum `migration_fee_percentage` the DBC config must route to the treasury.
    pub min_treasury_pct: u8,
    /// Quote amount harvested into the treasury at graduation.
    pub funded_amount: u64,
    /// Quote amount already released to the team.
    pub released_amount: u64,
    /// Extra quote collected after funding: DBC partner trading fees, partner surplus and
    /// DAMM v2 LP fees of the treasury-owned position. Never released to the team: it backs NAV.
    pub fees_collected: u64,

    /// Share of `funded_amount` kept forever as a floor reserve (bps). Tranches split the rest.
    pub floor_reserve_bps: u16,
    /// Quote spent by `defend_floor` buying tokens below backing.
    pub floor_spent: u64,
    /// Base tokens bought back by `defend_floor` and burned.
    pub tokens_burned: u64,

    pub milestones: [Milestone; MAX_MILESTONES],
    pub milestone_count: u8,

    /// Seconds holders have to reject a proposed tranche.
    pub challenge_window: i64,
    /// Share of base-token supply (bps) that must lock "reject" votes to block a tranche.
    pub reject_quorum_bps: u16,

    /// Active proposal (valid while a milestone is `Proposed`).
    pub proposal_nonce: u32,
    pub proposal_milestone: u8,
    pub proposal_ends_at: i64,
    pub proposal_reject_weight: u64,
    /// Link to the delivered work for the active (or last) tranche request.
    #[max_len(160)]
    pub proposal_evidence_uri: String,

    pub bump: u8,
    pub treasury_bump: u8,
}

/// A holder's locked "reject" vote on one proposal.
#[account]
#[derive(InitSpace)]
pub struct VoteRecord {
    pub raise: Pubkey,
    pub voter: Pubkey,
    pub proposal_nonce: u32,
    pub amount: u64,
    pub bump: u8,
}
OWNCURVE_EOF

mkdir -p 'programs/owncurve/src'
cat > 'programs/owncurve/src/errors.rs' <<'OWNCURVE_EOF'
use anchor_lang::prelude::*;

#[error_code]
pub enum OwnCurveError {
    #[msg("Invalid milestone configuration (1-5 milestones, tranches must sum to 10000 bps)")]
    InvalidMilestones,
    #[msg("Invalid governance parameters")]
    InvalidGovernance,
    #[msg("Raise is not in the required state for this action")]
    InvalidState,
    #[msg("DBC account is not owned by the DBC program or has the wrong type")]
    InvalidDbcAccount,
    #[msg("DBC pool does not belong to this raise's config")]
    PoolConfigMismatch,
    #[msg("DBC config fee_claimer must be the raise treasury PDA")]
    FeeClaimerNotTreasury,
    #[msg("DBC config leftover_receiver must be the raise treasury PDA")]
    LeftoverReceiverNotTreasury,
    #[msg("DBC config must not share the migration fee with the creator")]
    CreatorMigrationFeeNotZero,
    #[msg("DBC config migration fee is below the raise's minimum treasury share")]
    TreasuryShareTooLow,
    #[msg("DBC pool creator must be the raise team")]
    PoolCreatorNotTeam,
    #[msg("Creator LP must be 100% permanently locked (no unlocked or vesting LP)")]
    CreatorLpNotLocked,
    #[msg("DBC config must not give the mint authority to the creator")]
    CreatorMintAuthority,
    #[msg("Bonding curve has not completed yet")]
    CurveNotComplete,
    #[msg("Only the team can do this")]
    NotTeam,
    #[msg("Milestones must be proposed in order")]
    MilestoneOutOfOrder,
    #[msg("A proposal is already active")]
    ProposalActive,
    #[msg("No active proposal")]
    NoActiveProposal,
    #[msg("Challenge window is still open")]
    ChallengeWindowOpen,
    #[msg("Challenge window has closed")]
    ChallengeWindowClosed,
    #[msg("Vote belongs to a proposal that is still active")]
    VoteStillLocked,
    #[msg("Amount must be greater than zero")]
    ZeroAmount,
    #[msg("Math overflow")]
    MathOverflow,
    #[msg("A tranche request needs a link to the delivered work (1-160 characters)")]
    InvalidEvidence,
    #[msg("Floor buyback exceeds the floor reserve plus collected fees")]
    FloorBudgetExceeded,
    #[msg("Nothing to buy back: the treasury or the circulating supply is empty")]
    NothingToDefend,
}
OWNCURVE_EOF

mkdir -p 'scripts/lib'
cat > 'scripts/lib/net.ts' <<'OWNCURVE_EOF'
// Red de trabajo: devnet real, o LiteSVM en memoria (para tests locales con los
// binarios reales de DBC). Ambos exponen lo mismo: `conn` (tipo Connection) y `send`.
import {
  Connection,
  Keypair,
  PublicKey,
  SystemProgram,
  Transaction,
  TransactionInstruction,
  ComputeBudgetProgram,
  sendAndConfirmTransaction,
} from "@solana/web3.js";
import fs from "fs";
import os from "os";
import path from "path";

export type Net = {
  cluster: "devnet" | "local";
  conn: Connection;
  payer: Keypair;
  send: (label: string, ixs: TransactionInstruction[], signers: Keypair[]) => Promise<string>;
  explorer: (sig: string) => string;
  /** local: adelanta el reloj del validador; devnet: espera de verdad. */
  advanceTime: (secs: number) => Promise<void>;
  /** local: airdrop; devnet: transferencia desde la wallet principal. */
  fund: (to: PublicKey, lamports: number) => Promise<void>;
  svm?: any;
};

export function loadKeypair(file: string): Keypair {
  const p = file.startsWith("~") ? path.join(os.homedir(), file.slice(1)) : file;
  return Keypair.fromSecretKey(Uint8Array.from(JSON.parse(fs.readFileSync(p, "utf8"))));
}

export async function makeNet(): Promise<Net> {
  const cluster = (process.env.CLUSTER ?? "devnet") as "devnet" | "local";
  if (cluster === "local") return makeLocal();

  const url = process.env.RPC_URL ?? "https://api.devnet.solana.com";
  const conn = new Connection(url, "confirmed");
  // RPC local sin websocket (el servidor de tests sobre LiteSVM): confirmar consultando.
  const pollOnly = /^http:\/\/(localhost|127\.0\.0\.1)/.test(url);
  const payer = loadKeypair(process.env.WALLET ?? "~/.config/solana/id.json");
  const send = async (label: string, ixs: TransactionInstruction[], signers: Keypair[]) => {
    const tx = new Transaction().add(
      ...withBudget(ixs, [
        ComputeBudgetProgram.setComputeUnitLimit({ units: 1_000_000 }),
        ComputeBudgetProgram.setComputeUnitPrice({ microLamports: 20_000 }),
      ]),
    );
    tx.feePayer = payer.publicKey;
    let lastErr: unknown;
    for (let attempt = 1; attempt <= 3; attempt++) {
      try {
        if (pollOnly) return await sendAndPoll(conn, tx, dedupe([payer, ...signers]));
        const sig = await sendAndConfirmTransaction(conn, tx, dedupe([payer, ...signers]), {
          commitment: "confirmed",
        });
        return sig;
      } catch (e: any) {
        lastErr = e;
        const logs: string[] | undefined = e?.logs ?? e?.transactionLogs;
        const msg = String(e?.message ?? e);
        // Errores del programa: no tiene sentido reintentar.
        if (logs || /custom program error|Simulation failed/i.test(msg)) {
          throw new TxError(label, msg, logs);
        }
        console.log(`   … ${label}: reintento ${attempt}/3 (${msg.slice(0, 80)})`);
        await new Promise((r) => setTimeout(r, 2500 * attempt));
      }
    }
    throw new TxError(label, String((lastErr as any)?.message ?? lastErr));
  };
  return {
    // un RPC local (LiteSVM detrás de JSON-RPC) usa la config local de DAMM v2
    cluster: pollOnly ? "local" : cluster,
    conn,
    payer,
    send,
    explorer: (sig) => `https://explorer.solana.com/tx/${sig}?cluster=devnet`,
    advanceTime: (secs) => new Promise((r) => setTimeout(r, (secs + 2) * 1000)),
    fund: async (to, lamports) => {
      await send("fondear", [SystemProgram.transfer({ fromPubkey: payer.publicKey, toPubkey: to, lamports })], []);
    },
  };
}

async function sendAndPoll(conn: Connection, tx: Transaction, signers: Keypair[]) {
  tx.recentBlockhash = (await conn.getLatestBlockhash("confirmed")).blockhash;
  tx.sign(...signers);
  const sig = await conn.sendRawTransaction(tx.serialize(), { preflightCommitment: "confirmed" });
  for (let i = 0; i < 60; i++) {
    const st = (await conn.getSignatureStatuses([sig])).value[0];
    if (st?.err) throw new Error(`Transaction ${sig} failed: ${JSON.stringify(st.err)}`);
    if (st) return sig;
    await new Promise((r) => setTimeout(r, 500));
  }
  throw new Error(`Transaction ${sig} not confirmed`);
}

export class TxError extends Error {
  constructor(public label: string, message: string, public logs?: string[]) {
    super(`${label}: ${message}`);
  }
}

// Añade nuestras instrucciones de ComputeBudget solo si la transacción (p. ej. del SDK
// de Meteora) no trae ya las suyas: Solana rechaza instrucciones de presupuesto duplicadas.
function withBudget(ixs: TransactionInstruction[], budget: TransactionInstruction[]) {
  const present = new Set(
    ixs.filter((ix) => ix.programId.equals(ComputeBudgetProgram.programId)).map((ix) => ix.data[0]),
  );
  return [...budget.filter((ix) => !present.has(ix.data[0])), ...ixs];
}

function dedupe(kps: Keypair[]): Keypair[] {
  const seen = new Set<string>();
  return kps.filter((k) => !seen.has(k.publicKey.toBase58()) && seen.add(k.publicKey.toBase58()));
}

// ---------------------------------------------------------------------------
// LiteSVM: validador en memoria con los .so reales de DBC y de OwnCurve.
// ---------------------------------------------------------------------------
async function makeLocal(): Promise<Net> {
  const { LiteSVM, FailedTransactionMetadata } = await import("litesvm");
  const svm = new LiteSVM();
  const so = (env: string, def: string) => process.env[env] ?? def;
  const DBC = new PublicKey("dbcij3LWUppWqq96dh6gJWwBifmcGfLSB5D4DuSMaqN");
  const DAMM_V2 = new PublicKey("cpamdpZCGKUy5JxQXB4dcpGPiikHawvSWAd6mEn1sGG");
  const idl = JSON.parse(fs.readFileSync("target/idl/owncurve.json", "utf8"));
  svm.addProgramFromFile(DBC, so("DBC_SO", "local/dynamic_bonding_curve.so"));
  if (fs.existsSync(so("DAMM_V2_SO", "local/damm_v2.so"))) {
    svm.addProgramFromFile(DAMM_V2, so("DAMM_V2_SO", "local/damm_v2.so"));
  }
  svm.addProgramFromFile(new PublicKey(idl.address), "target/deploy/owncurve.so");

  // Igual que en mainnet/devnet: la pool authority de DBC tiene lamports para "flash rent".
  const [poolAuthority] = PublicKey.findProgramAddressSync([Buffer.from("pool_authority")], DBC);
  svm.setAccount(poolAuthority, {
    lamports: 1_000_000_000,
    data: new Uint8Array(),
    owner: new PublicKey("11111111111111111111111111111111"),
    executable: false,
  });

  // Mint de SOL envuelto (wSOL), como en los tests de DBC: 9 decimales, inicializado.
  const nativeMint = new Uint8Array(82);
  nativeMint[44] = 9;
  nativeMint[45] = 1;
  svm.setAccount(new PublicKey("So11111111111111111111111111111111111111112"), {
    lamports: 1_390_379_946_687,
    data: nativeMint,
    owner: new PublicKey("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"),
    executable: false,
  });

  const payer = Keypair.generate();
  svm.airdrop(payer.publicKey, BigInt(100e9));
  const conn = new SvmConnection(svm) as unknown as Connection;

  const send = async (label: string, ixs: TransactionInstruction[], signers: Keypair[]) => {
    const tx = new Transaction().add(
      ...withBudget(ixs, [ComputeBudgetProgram.setComputeUnitLimit({ units: 1_400_000 })]),
    );
    tx.feePayer = payer.publicKey;
    tx.recentBlockhash = svm.latestBlockhash();
    tx.sign(...dedupe([payer, ...signers]));
    if (process.env.DEBUG) console.log(`   [svm] ${label}: ${tx.instructions.length} ix, ${tx.serialize().length} bytes`);
    const res = svm.sendTransaction(tx);
    svm.expireBlockhash();
    if (res instanceof FailedTransactionMetadata) {
      throw new TxError(label, res.err().toString(), res.meta().logs());
    }
    return Buffer.from(tx.signature!).toString("hex").slice(0, 16);
  };
  const advanceTime = async (secs: number) => {
    const c = svm.getClock();
    c.unixTimestamp = c.unixTimestamp + BigInt(secs);
    c.slot = c.slot + BigInt(Math.max(1, Math.ceil(secs * 2.5)));
    svm.setClock(c);
  };
  const fund = async (to: PublicKey, lamports: number) => {
    svm.airdrop(to, BigInt(lamports));
  };
  return { cluster: "local", conn, payer, send, explorer: (s) => `local:${s}`, advanceTime, fund, svm };
}

// Lo mínimo de Connection que usan Anchor y el SDK de DBC, respaldado por LiteSVM.
class SvmConnection {
  commitment = "confirmed";
  rpcEndpoint = "litesvm";
  constructor(private svm: any) {}
  private info(pk: PublicKey) {
    const a = this.svm.getAccount(pk);
    // LiteSVM devuelve las cuentas cerradas como vacías; una RPC real devuelve null.
    if (!a || (Number(a.lamports) === 0 && a.data.length === 0)) return null;
    return {
      data: Buffer.from(a.data),
      executable: a.executable,
      lamports: Number(a.lamports),
      owner: new PublicKey(a.owner),
      rentEpoch: 0,
    };
  }
  private ctx() {
    return { slot: Number(this.svm.getClock().slot) };
  }
  async getAccountInfo(pk: PublicKey) {
    return this.info(pk);
  }
  async getAccountInfoAndContext(pk: PublicKey) {
    return { context: this.ctx(), value: this.info(pk) };
  }
  async getMultipleAccountsInfo(pks: PublicKey[]) {
    return pks.map((p) => this.info(p));
  }
  async getMultipleAccountsInfoAndContext(pks: PublicKey[]) {
    return { context: this.ctx(), value: pks.map((p) => this.info(p)) };
  }
  async getSlot() {
    return Number(this.svm.getClock().slot);
  }
  async getBlockTime() {
    return Number(this.svm.getClock().unixTimestamp);
  }
  async getBalance(pk: PublicKey) {
    return Number(this.svm.getBalance(pk) ?? 0n);
  }
  async getLatestBlockhash() {
    return { blockhash: this.svm.latestBlockhash(), lastValidBlockHeight: 1_000_000_000 };
  }
  async getMinimumBalanceForRentExemption(n: number) {
    return Number(this.svm.minimumBalanceForRentExemption(BigInt(n)));
  }
  async getTokenAccountBalance(pk: PublicKey) {
    const a = this.info(pk);
    const amount = a ? Buffer.from(a.data).readBigUInt64LE(64) : 0n;
    return { context: this.ctx(), value: { amount: amount.toString(), decimals: 9, uiAmount: Number(amount) / 1e9 } };
  }
}

/** Carga el IDL compilado (solo Node). */
export function loadIdl(path = "target/idl/owncurve.json") {
  return JSON.parse(fs.readFileSync(path, "utf8"));
}
OWNCURVE_EOF

mkdir -p 'scripts/lib'
cat > 'scripts/lib/owncurve.ts' <<'OWNCURVE_EOF'
// Cliente de OwnCurve: todas las operaciones del ciclo de vida de un raise.
// Lo usan el script de devnet (scripts/f1.ts) y los tests (tests/owncurve.test.ts).
import { AnchorProvider, BN, Program, Wallet } from "@anchor-lang/core";
import {
  ActivationType,
  BaseFeeMode,
  CollectFeeMode,
  DAMM_V2_MIGRATION_FEE_ADDRESS,
  DammV2DynamicFeeMode,
  DynamicBondingCurveClient,
  MigratedCollectFeeMode,
  MigrationFeeOption,
  MigrationOption,
  SwapMode,
  TokenAuthorityOption,
  TokenDecimal,
  TokenType,
  buildCurve,
  createDammV2Program,
  deriveDammV2EventAuthority,
  deriveDammV2PoolAddress,
  deriveDammV2PoolAuthority,
  deriveDammV2TokenVaultAddress,
  deriveDbcEventAuthority,
  deriveDbcPoolAddress,
  deriveDbcPoolAuthority,
  getCurrentPoint,
} from "@meteora-ag/dynamic-bonding-curve-sdk";
import {
  NATIVE_MINT,
  TOKEN_2022_PROGRAM_ID,
  TOKEN_PROGRAM_ID,
  createAssociatedTokenAccountIdempotentInstruction,
  createSyncNativeInstruction,
  createTransferCheckedInstruction,
  getAssociatedTokenAddressSync,
} from "@solana/spl-token";
import { Keypair, PublicKey, SystemProgram, TransactionInstruction } from "@solana/web3.js";
import { createLocalDammV2Config } from "./local-damm";
import type { Net } from "./net";

export const DBC = new PublicKey("dbcij3LWUppWqq96dh6gJWwBifmcGfLSB5D4DuSMaqN");
export const DAMM_V2 = new PublicKey("cpamdpZCGKUy5JxQXB4dcpGPiikHawvSWAd6mEn1sGG");
export const BASE_DECIMALS = 6;

export type RaiseParams = {
  thresholdSol: number;
  treasuryPct: number; // % de lo recaudado que va a la tesorería (migration fee)
  tranchesBps: number[];
  challengeSecs: number;
  quorumBps: number;
  floorReserveBps: number; // parte de lo recaudado que nunca se paga: respalda el piso de precio
  // Solo para tests de seguridad: configs DBC "maliciosas".
  feeClaimer?: PublicKey;
  creatorMigrationFeePct?: number;
  creatorUnlockedLpPct?: number;
};

export const DEFAULT_PARAMS: RaiseParams = {
  thresholdSol: 0.5,
  treasuryPct: 80,
  tranchesBps: [3000, 3000, 4000],
  challengeSecs: 60,
  quorumBps: 1000,
  floorReserveBps: 2000,
};

export type Evidence = { uri: string; hash: number[] };

/** SHA-256 en Node y en el navegador. */
export async function sha256(text: string): Promise<number[]> {
  const data = new TextEncoder().encode(text);
  const buf = await (globalThis.crypto as Crypto).subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(buf));
}

export async function evidence(uri: string, committed?: string): Promise<Evidence> {
  return { uri, hash: await sha256(committed?.trim() || uri) };
}

export const ps = (p: any) => p.poolState ?? p; // SDK ≥1.5.8 anida el estado del pool
export const stateName = (s: any) => Object.keys(s)[0];

export function curveConfig(p: RaiseParams) {
  // Con t% a la tesorería, solo (100−t)% de lo recaudado entra al pool: el % de suministro
  // que migra debe ser s < (1−t)(1−s) para que el precio de graduación quede por encima
  // de la curva. Para t=80 ⇒ s < 16,7%. Usamos la mitad del límite.
  const r = 1 - p.treasuryPct / 100;
  const supplyPct = Math.max(1, Math.floor(((r / (1 + r)) * 100) / 2));
  return buildCurve({
    token: {
      tokenType: TokenType.Token2022,
      tokenBaseDecimal: TokenDecimal.SIX,
      tokenQuoteDecimal: TokenDecimal.NINE,
      tokenAuthorityOption: TokenAuthorityOption.Immutable,
      totalTokenSupply: 1_000_000_000,
      leftover: 0,
    },
    fee: {
      baseFeeParams: {
        baseFeeMode: BaseFeeMode.FeeSchedulerLinear,
        feeSchedulerParam: { startingFeeBps: 100, endingFeeBps: 100, numberOfPeriod: 0, totalDuration: 0 },
      },
      dynamicFeeEnabled: false,
      collectFeeMode: CollectFeeMode.QuoteToken,
      creatorTradingFeePercentage: 0,
      poolCreationFee: 0,
      enableFirstSwapWithMinFee: false,
    },
    migration: {
      migrationOption: MigrationOption.MET_DAMM_V2,
      migrationFeeOption: MigrationFeeOption.Customizable,
      migrationFee: { feePercentage: p.treasuryPct, creatorFeePercentage: p.creatorMigrationFeePct ?? 0 },
      migratedPoolFee: {
        collectFeeMode: MigratedCollectFeeMode.QuoteToken,
        dynamicFee: DammV2DynamicFeeMode.Disabled,
        poolFeeBps: 100,
      },
    },
    // El LP graduado queda 100% bloqueado a nombre del partner = la tesorería.
    liquidityDistribution: {
      partnerPermanentLockedLiquidityPercentage: 100 - (p.creatorUnlockedLpPct ?? 0),
      partnerLiquidityPercentage: 0,
      creatorPermanentLockedLiquidityPercentage: 0,
      creatorLiquidityPercentage: p.creatorUnlockedLpPct ?? 0,
    },
    lockedVesting: {
      totalLockedVestingAmount: 0,
      numberOfVestingPeriod: 0,
      cliffUnlockAmount: 0,
      totalVestingDuration: 0,
      cliffDurationFromMigrationTime: 0,
    },
    activationType: ActivationType.Timestamp,
    percentageSupplyOnMigration: supplyPct,
    migrationQuoteThreshold: p.thresholdSol,
  });
}

export class Raise {
  constructor(
    readonly oc: OwnCurve,
    readonly config: PublicKey,
    readonly baseMint: PublicKey,
  ) {}
  get pid() {
    return this.oc.programId;
  }
  get raise() {
    return PublicKey.findProgramAddressSync([Buffer.from("raise"), this.config.toBuffer()], this.pid)[0];
  }
  get treasury() {
    return PublicKey.findProgramAddressSync([Buffer.from("treasury"), this.config.toBuffer()], this.pid)[0];
  }
  get escrow() {
    return PublicKey.findProgramAddressSync([Buffer.from("escrow"), this.raise.toBuffer()], this.pid)[0];
  }
  get pool() {
    return deriveDbcPoolAddress(NATIVE_MINT, this.baseMint, this.config);
  }
  get treasuryQuote() {
    return getAssociatedTokenAddressSync(NATIVE_MINT, this.treasury, true);
  }
  get treasuryBase() {
    return getAssociatedTokenAddressSync(this.baseMint, this.treasury, true, TOKEN_2022_PROGRAM_ID);
  }
  get escrowBase() {
    return getAssociatedTokenAddressSync(this.baseMint, this.escrow, true, TOKEN_2022_PROGRAM_ID);
  }
  baseAta(owner: PublicKey) {
    return getAssociatedTokenAddressSync(this.baseMint, owner, true, TOKEN_2022_PROGRAM_ID);
  }
  quoteAta(owner: PublicKey) {
    return getAssociatedTokenAddressSync(NATIVE_MINT, owner, true);
  }
  voteRecord(voter: PublicKey, nonce: number) {
    return PublicKey.findProgramAddressSync(
      [Buffer.from("vote"), this.raise.toBuffer(), voter.toBuffer(), new BN(nonce).toArrayLike(Buffer, "le", 4)],
      this.pid,
    )[0];
  }
  async fetch(): Promise<any> {
    return (this.oc.program.account as any).raise.fetch(this.raise);
  }
  async fetchNullable(): Promise<any> {
    return (this.oc.program.account as any).raise.fetchNullable(this.raise);
  }
  async state(): Promise<string> {
    return stateName((await this.fetch()).state);
  }
}

export class OwnCurve {
  readonly program: Program<any>;
  readonly dbc: DynamicBondingCurveClient;
  readonly programId: PublicKey;

  constructor(readonly net: Net, idl: any) {
    this.programId = new PublicKey(idl.address);
    // Solo construimos instrucciones (nunca .rpc()), así que el "wallet" del provider
    // no firma nada: basta con la clave pública. Funciona igual en Node y en el navegador.
    const wallet = {
      publicKey: net.payer.publicKey,
      signTransaction: async (t: any) => t,
      signAllTransactions: async (t: any) => t,
    } as unknown as Wallet;
    const provider = new AnchorProvider(net.conn, wallet, { commitment: "confirmed" });
    this.program = new Program(idl, provider) as Program<any>;
    this.dbc = new DynamicBondingCurveClient(net.conn, "confirmed");
  }
  get payer() {
    return this.net.payer.publicKey;
  }
  get m() {
    return this.program.methods as any;
  }

  // ---------------------------------------------------------------- creación
  /** init_raise + create_config de DBC en UNA transacción. */
  async createRaise(params: RaiseParams, configKp = Keypair.generate(), team = this.net.payer) {
    const r = new Raise(this, configKp.publicKey, PublicKey.default);
    const initRaise = await this.m
      .initRaise({
        minTreasuryPct: params.treasuryPct,
        trancheBps: params.tranchesBps,
        challengeWindow: new BN(params.challengeSecs),
        rejectQuorumBps: params.quorumBps,
        floorReserveBps: params.floorReserveBps,
      })
      .accountsStrict({
        team: team.publicKey,
        dbcConfig: configKp.publicKey,
        raise: r.raise,
        treasury: r.treasury,
        systemProgram: SystemProgram.programId,
      })
      .instruction();
    const createConfig = await this.dbc.partner.createConfig({
      config: configKp.publicKey,
      feeClaimer: params.feeClaimer ?? r.treasury,
      leftoverReceiver: r.treasury,
      payer: this.payer,
      quoteMint: NATIVE_MINT,
      ...curveConfig(params),
    });
    const sig = await this.net.send("init_raise + create_config", [initRaise, ...createConfig.instructions], [
      configKp,
      team,
    ]);
    return { sig, configKp };
  }

  /** create_pool de DBC + bind_pool en UNA transacción: el launch nace validado. */
  async launchPool(
    config: PublicKey,
    baseMintKp = Keypair.generate(),
    team = this.net.payer,
    withPool = true,
    meta: { name: string; symbol: string; uri: string } = {
      name: "OwnCurve Demo",
      symbol: "OWND",
      uri: "https://raw.githubusercontent.com/solana-developers/opos-asset/main/assets/DeveloperPortal/metadata.json",
    },
  ) {
    const r = new Raise(this, config, baseMintKp.publicKey);
    const ixs: TransactionInstruction[] = [];
    if (withPool && !(await this.net.conn.getAccountInfo(r.pool))) {
      const createPool = await this.dbc.creator.createPool({
        baseMint: baseMintKp.publicKey,
        config,
        ...meta,
        payer: this.payer,
        poolCreator: team.publicKey,
      });
      ixs.push(...createPool.instructions);
    }
    ixs.push(
      await this.m
        .bindPool()
        .accountsStrict({ raise: r.raise, treasury: r.treasury, dbcConfig: config, dbcPool: r.pool })
        .instruction(),
    );
    const sig = await this.net.send("create_pool + bind_pool", ixs, ixs.length > 1 ? [baseMintKp, team] : []);
    return { sig, raise: r };
  }

  // ---------------------------------------------------------------- curva
  /** Compra en la curva con `lamportsIn` de SOL. PartialFill nunca pasa del umbral;
   *  ExactIn puede pasarse y deja un excedente ("surplus") en el pool. */
  async buy(r: Raise, lamportsIn: BN, buyer = this.net.payer, mode: SwapMode.PartialFill | SwapMode.ExactIn = SwapMode.PartialFill) {
    const cfg = await this.dbc.state.getPoolConfig(r.config);
    const pool = await this.dbc.state.getPool(r.pool);
    const quote = this.dbc.pool.swapQuote2({
      virtualPool: pool as any,
      config: cfg!,
      swapBaseForQuote: false,
      hasReferral: false,
      eligibleForFirstSwapWithMinFee: false,
      currentPoint: await getCurrentPoint(this.net.conn, cfg!.activationType),
      slippageBps: 500,
      swapMode: mode,
      amountIn: lamportsIn,
    });
    const swap = await this.dbc.pool.swap2({
      owner: buyer.publicKey,
      pool: r.pool,
      swapBaseForQuote: false,
      referralTokenAccount: null,
      payer: buyer.publicKey,
      swapMode: mode,
      amountIn: lamportsIn,
      minimumAmountOut: quote.minimumAmountOut ?? new BN(0),
    });
    return this.net.send("compra en la curva", swap.instructions, [buyer]);
  }

  async curve(r: Raise) {
    const cfg = await this.dbc.state.getPoolConfig(r.config);
    const pool = ps(await this.dbc.state.getPool(r.pool));
    const threshold = new BN(cfg!.migrationQuoteThreshold.toString());
    const reserve = new BN(pool.quoteReserve.toString());
    return { cfg: cfg!, pool, threshold, reserve, complete: reserve.gte(threshold) };
  }

  async buyToComplete(r: Raise, buyer = this.net.payer) {
    const sigs: string[] = [];
    for (let i = 0; i < 8; i++) {
      const c = await this.curve(r);
      if (c.complete) return sigs;
      const remaining = c.threshold.sub(c.reserve);
      sigs.push(await this.buy(r, remaining.muln(103).divn(100).addn(10_000), buyer));
    }
    throw new Error("La curva no se completó tras 8 compras");
  }

  // ---------------------------------------------------------------- tesorería
  private dbcAccounts(r: Raise, pool: any) {
    return {
      dbcPoolAuthority: deriveDbcPoolAuthority(),
      dbcConfig: r.config,
      dbcPool: r.pool,
      dbcQuoteVault: pool.quoteVault,
      dbcEventAuthority: deriveDbcEventAuthority(),
      dbcProgram: DBC,
    };
  }

  private ensureTreasuryAtas(r: Raise) {
    return [
      createAssociatedTokenAccountIdempotentInstruction(this.payer, r.treasuryQuote, r.treasury, NATIVE_MINT),
      createAssociatedTokenAccountIdempotentInstruction(
        this.payer,
        r.treasuryBase,
        r.treasury,
        r.baseMint,
        TOKEN_2022_PROGRAM_ID,
      ),
    ];
  }

  async harvest(r: Raise) {
    const { pool } = await this.curve(r);
    const ix = await this.m
      .harvest()
      .accountsStrict({
        raise: r.raise,
        treasury: r.treasury,
        treasuryQuote: r.treasuryQuote,
        quoteMint: NATIVE_MINT,
        ...this.dbcAccounts(r, pool),
        quoteTokenProgram: TOKEN_PROGRAM_ID,
      })
      .instruction();
    return this.net.send("harvest", [...this.ensureTreasuryAtas(r), ix], []);
  }

  async collectTradingFees(r: Raise) {
    const { pool } = await this.curve(r);
    const ix = await this.m
      .collectTradingFees()
      .accountsStrict({
        raise: r.raise,
        treasury: r.treasury,
        treasuryBase: r.treasuryBase,
        treasuryQuote: r.treasuryQuote,
        baseMint: r.baseMint,
        quoteMint: NATIVE_MINT,
        ...this.dbcAccounts(r, pool),
        dbcBaseVault: pool.baseVault,
        baseTokenProgram: TOKEN_2022_PROGRAM_ID,
        quoteTokenProgram: TOKEN_PROGRAM_ID,
      })
      .instruction();
    return this.net.send("collect_trading_fees", [...this.ensureTreasuryAtas(r), ix], []);
  }

  async collectSurplus(r: Raise) {
    const { pool } = await this.curve(r);
    const ix = await this.m
      .collectSurplus()
      .accountsStrict({
        raise: r.raise,
        treasury: r.treasury,
        treasuryQuote: r.treasuryQuote,
        quoteMint: NATIVE_MINT,
        ...this.dbcAccounts(r, pool),
        quoteTokenProgram: TOKEN_PROGRAM_ID,
      })
      .instruction();
    return this.net.send("collect_surplus", [ix], []);
  }

  // ---------------------------------------------------------------- DAMM v2
  async dammConfig(): Promise<PublicKey> {
    return this.net.cluster === "local"
      ? createLocalDammV2Config(this.net)
      : DAMM_V2_MIGRATION_FEE_ADDRESS[MigrationFeeOption.Customizable];
  }

  async dammPool(r: Raise) {
    return deriveDammV2PoolAddress(await this.dammConfig(), r.baseMint, NATIVE_MINT);
  }

  async migrate(r: Raise) {
    const m = await this.dbc.migration.migrateToDammV2({
      payer: this.payer,
      pool: r.pool,
      dammConfig: await this.dammConfig(),
    });
    const sig = await this.net.send("migrate_damm_v2", m.transaction.instructions, [
      m.firstPositionNftKeypair,
      m.secondPositionNftKeypair,
    ]);
    return { sig, nftMints: [m.firstPositionNftKeypair.publicKey, m.secondPositionNftKeypair.publicKey] };
  }

  /** De las posiciones creadas al migrar, devuelve la que pertenece a la tesorería. */
  async treasuryPosition(r: Raise, nftMints: PublicKey[]) {
    for (const mint of nftMints) {
      const nftAccount = PublicKey.findProgramAddressSync([Buffer.from("position_nft_account"), mint.toBuffer()], DAMM_V2)[0];
      const info = await this.net.conn.getAccountInfo(nftAccount);
      if (info && new PublicKey(info.data.subarray(32, 64)).equals(r.treasury)) {
        const position = PublicKey.findProgramAddressSync([Buffer.from("position"), mint.toBuffer()], DAMM_V2)[0];
        return { nftMint: mint, nftAccount, position };
      }
    }
    throw new Error("Ninguna posición de DAMM v2 pertenece a la tesorería");
  }

  async claimLpFees(r: Raise, pos: { nftAccount: PublicKey; position: PublicKey }) {
    const pool = await this.dammPool(r);
    const ix = await this.m
      .claimLpFees()
      .accountsStrict({
        raise: r.raise,
        treasury: r.treasury,
        treasuryBase: r.treasuryBase,
        treasuryQuote: r.treasuryQuote,
        baseMint: r.baseMint,
        quoteMint: NATIVE_MINT,
        dammPoolAuthority: deriveDammV2PoolAuthority(),
        dammPool: pool,
        position: pos.position,
        dammBaseVault: deriveDammV2TokenVaultAddress(pool, r.baseMint),
        dammQuoteVault: deriveDammV2TokenVaultAddress(pool, NATIVE_MINT),
        positionNftAccount: pos.nftAccount,
        dammEventAuthority: deriveDammV2EventAuthority(),
        dammProgram: DAMM_V2,
        baseTokenProgram: TOKEN_2022_PROGRAM_ID,
        quoteTokenProgram: TOKEN_PROGRAM_ID,
      })
      .instruction();
    return this.net.send("claim_lp_fees", [...this.ensureTreasuryAtas(r), ix], []);
  }

  // ---------------------------------------------------------------- piso de precio
  /** Estado del pool DAMM v2 graduado: reservas y precio (lamports por unidad base). */
  async dammState(r: Raise) {
    const damm = createDammV2Program(this.net.conn) as any;
    const pool = await this.dammPool(r);
    const info = await this.net.conn.getAccountInfo(pool);
    if (!info) return null;
    const p = damm.coder.accounts.decode("pool", info.data);
    const sqrt = BigInt(p.sqrtPrice.toString());
    // precio = (sqrt / 2^64)^2 en unidades atómicas (lamports por unidad base)
    const price = Number((sqrt * sqrt) >> 64n) / 2 ** 64;
    return {
      pool,
      baseReserve: new BN(p.tokenAAmount.toString()),
      quoteReserve: new BN(p.tokenBAmount.toString()),
      price,
    };
  }

  /** Respaldo por unidad base: lo que la tesorería tiene por cada token en circulación. */
  async backing(r: Raise) {
    const treasuryQuote = await this.tokenBalance(r.treasuryQuote);
    const circulating = (await this.mintSupply(r.baseMint)).sub(await this.tokenBalance(r.treasuryBase));
    const perUnit = circulating.isZero() ? 0 : Number(treasuryQuote.toString()) / Number(circulating.toString());
    return { treasuryQuote, circulating, perUnit };
  }

  /** Presupuesto restante para defender el piso: reserva + comisiones − gastado. */
  async floorBudget(r: Raise) {
    const raise = await r.fetch();
    const funded = new BN(raise.fundedAmount.toString());
    const reserve = funded.muln(raise.floorReserveBps).divn(10_000);
    const b = reserve.add(new BN(raise.feesCollected.toString())).sub(new BN(raise.floorSpent.toString()));
    return b.isNeg() ? new BN(0) : b;
  }

  /** SOL que conviene gastar para devolver el precio al respaldo (aprox. producto constante,
   *  descontando la comisión del pool), acotado por el presupuesto. 0 si el precio ya está arriba. */
  async suggestDefend(r: Raise): Promise<BN> {
    const st = await this.dammState(r);
    if (!st) return new BN(0);
    const { perUnit } = await this.backing(r);
    if (!(perUnit > 0) || st.price >= perUnit) return new BN(0);
    const q = Number(st.quoteReserve.toString());
    const b = Number(st.baseReserve.toString());
    const target = Math.sqrt(q * b * perUnit); // reserva de SOL con la que precio = respaldo
    const gap = Math.max(0, (target - q) * 0.9); // margen: comisión y redondeos
    const budget = await this.floorBudget(r);
    return BN.min(new BN(Math.floor(gap).toString()), budget);
  }

  async defendFloor(r: Raise, amountIn: BN) {
    const pool = await this.dammPool(r);
    const ix = await this.m
      .defendFloor(amountIn)
      .accountsStrict({
        raise: r.raise,
        treasury: r.treasury,
        treasuryBase: r.treasuryBase,
        treasuryQuote: r.treasuryQuote,
        baseMint: r.baseMint,
        quoteMint: NATIVE_MINT,
        dammPoolAuthority: deriveDammV2PoolAuthority(),
        dammPool: pool,
        dammBaseVault: deriveDammV2TokenVaultAddress(pool, r.baseMint),
        dammQuoteVault: deriveDammV2TokenVaultAddress(pool, NATIVE_MINT),
        dammEventAuthority: deriveDammV2EventAuthority(),
        dammProgram: DAMM_V2,
        baseTokenProgram: TOKEN_2022_PROGRAM_ID,
        quoteTokenProgram: TOKEN_PROGRAM_ID,
      })
      .instruction();
    return this.net.send("defend_floor", [...this.ensureTreasuryAtas(r), ix], []);
  }

  /** Swap token→SOL en DAMM v2 (para tests y demo: empujar el precio hacia abajo). */
  async dammSell(r: Raise, baseIn: BN, seller = this.net.payer) {
    const damm = createDammV2Program(this.net.conn) as any;
    const pool = await this.dammPool(r);
    const wsol = r.quoteAta(seller.publicKey);
    const ixs = [
      createAssociatedTokenAccountIdempotentInstruction(seller.publicKey, wsol, seller.publicKey, NATIVE_MINT),
      await damm.methods
        .swap({ amountIn: baseIn, minimumAmountOut: new BN(0) })
        .accountsPartial({
          poolAuthority: deriveDammV2PoolAuthority(),
          pool,
          inputTokenAccount: r.baseAta(seller.publicKey),
          outputTokenAccount: wsol,
          tokenAVault: deriveDammV2TokenVaultAddress(pool, r.baseMint),
          tokenBVault: deriveDammV2TokenVaultAddress(pool, NATIVE_MINT),
          tokenAMint: r.baseMint,
          tokenBMint: NATIVE_MINT,
          payer: seller.publicKey,
          tokenAProgram: TOKEN_2022_PROGRAM_ID,
          tokenBProgram: TOKEN_PROGRAM_ID,
          referralTokenAccount: null,
          eventAuthority: deriveDammV2EventAuthority(),
          program: DAMM_V2,
        })
        .instruction(),
    ];
    return this.net.send("venta en DAMM v2", ixs, [seller]);
  }

  /** Swap SOL→token en el pool DAMM v2 graduado (genera comisiones de LP). */
  async dammBuy(r: Raise, lamportsIn: BN, buyer = this.net.payer) {
    const damm = createDammV2Program(this.net.conn) as any;
    const pool = await this.dammPool(r);
    const wsol = r.quoteAta(buyer.publicKey);
    const out = r.baseAta(buyer.publicKey);
    const ixs = [
      createAssociatedTokenAccountIdempotentInstruction(buyer.publicKey, wsol, buyer.publicKey, NATIVE_MINT),
      createAssociatedTokenAccountIdempotentInstruction(buyer.publicKey, out, buyer.publicKey, r.baseMint, TOKEN_2022_PROGRAM_ID),
      SystemProgram.transfer({ fromPubkey: buyer.publicKey, toPubkey: wsol, lamports: BigInt(lamportsIn.toString()) }),
      createSyncNativeInstruction(wsol),
      await damm.methods
        .swap({ amountIn: lamportsIn, minimumAmountOut: new BN(0) })
        .accountsPartial({
          poolAuthority: deriveDammV2PoolAuthority(),
          pool,
          inputTokenAccount: wsol,
          outputTokenAccount: out,
          tokenAVault: deriveDammV2TokenVaultAddress(pool, r.baseMint),
          tokenBVault: deriveDammV2TokenVaultAddress(pool, NATIVE_MINT),
          tokenAMint: r.baseMint,
          tokenBMint: NATIVE_MINT,
          payer: buyer.publicKey,
          tokenAProgram: TOKEN_2022_PROGRAM_ID,
          tokenBProgram: TOKEN_PROGRAM_ID,
          referralTokenAccount: null,
          eventAuthority: deriveDammV2EventAuthority(),
          program: DAMM_V2,
        })
        .instruction(),
    ];
    return this.net.send("swap en DAMM v2", ixs, [buyer]);
  }

  // ---------------------------------------------------------------- gobernanza
  async propose(r: Raise, team = this.net.payer, ev?: Evidence) {
    const e = ev ?? (await evidence("https://github.com/owncurve/owncurve/releases"));
    const ix = await this.m
      .proposeRelease(e.uri, e.hash)
      .accountsStrict({ team: team.publicKey, raise: r.raise })
      .instruction();
    return this.net.send("propose_release", [ix], [team]);
  }

  async reject(r: Raise, voter: Keypair, amount: BN) {
    const raise = await r.fetch();
    const ix = await this.m
      .reject(amount)
      .accountsStrict({
        voter: voter.publicKey,
        raise: r.raise,
        vote: r.voteRecord(voter.publicKey, raise.proposalNonce),
        escrow: r.escrow,
        escrowBase: r.escrowBase,
        voterBase: r.baseAta(voter.publicKey),
        baseMint: r.baseMint,
        baseTokenProgram: TOKEN_2022_PROGRAM_ID,
        systemProgram: SystemProgram.programId,
      })
      .instruction();
    const ata = createAssociatedTokenAccountIdempotentInstruction(
      this.payer,
      r.escrowBase,
      r.escrow,
      r.baseMint,
      TOKEN_2022_PROGRAM_ID,
    );
    return this.net.send("reject", [ata, ix], [voter]);
  }

  async finalize(r: Raise) {
    const raise = await r.fetch();
    const teamQuote = r.quoteAta(raise.team);
    const ix = await this.m
      .finalize()
      .accountsStrict({
        raise: r.raise,
        treasury: r.treasury,
        treasuryQuote: r.treasuryQuote,
        treasuryBase: r.treasuryBase,
        teamQuote,
        quoteMint: NATIVE_MINT,
        baseMint: r.baseMint,
        quoteTokenProgram: TOKEN_PROGRAM_ID,
      })
      .instruction();
    return this.net.send(
      "finalize",
      [
        ...this.ensureTreasuryAtas(r),
        createAssociatedTokenAccountIdempotentInstruction(this.payer, teamQuote, raise.team, NATIVE_MINT),
        ix,
      ],
      [],
    );
  }

  async withdrawVote(r: Raise, voter: Keypair, nonce: number) {
    const ix = await this.m
      .withdrawVote()
      .accountsStrict({
        voter: voter.publicKey,
        raise: r.raise,
        vote: r.voteRecord(voter.publicKey, nonce),
        escrow: r.escrow,
        escrowBase: r.escrowBase,
        voterBase: r.baseAta(voter.publicKey),
        baseMint: r.baseMint,
        baseTokenProgram: TOKEN_2022_PROGRAM_ID,
      })
      .instruction();
    return this.net.send("withdraw_vote", [ix], [voter]);
  }

  async redeem(r: Raise, holder: Keypair, amount: BN) {
    const holderQuote = r.quoteAta(holder.publicKey);
    const ix = await this.m
      .redeem(amount)
      .accountsStrict({
        holder: holder.publicKey,
        raise: r.raise,
        treasury: r.treasury,
        treasuryQuote: r.treasuryQuote,
        treasuryBase: r.treasuryBase,
        holderBase: r.baseAta(holder.publicKey),
        holderQuote,
        baseMint: r.baseMint,
        quoteMint: NATIVE_MINT,
        baseTokenProgram: TOKEN_2022_PROGRAM_ID,
        quoteTokenProgram: TOKEN_PROGRAM_ID,
      })
      .instruction();
    return this.net.send(
      "redeem",
      [
        ...this.ensureTreasuryAtas(r),
        createAssociatedTokenAccountIdempotentInstruction(this.payer, holderQuote, holder.publicKey, NATIVE_MINT),
        ix,
      ],
      [holder],
    );
  }

  // ---------------------------------------------------------------- utilidades
  async tokenBalance(ata: PublicKey): Promise<BN> {
    const info = await this.net.conn.getAccountInfo(ata);
    // Cuenta inexistente o cerrada (p. ej. wSOL tras unwrap) ⇒ saldo 0.
    return info && info.data.length >= 72 ? new BN(info.data.readBigUInt64LE(64).toString()) : new BN(0);
  }

  async mintSupply(mint: PublicKey): Promise<BN> {
    const info = await this.net.conn.getAccountInfo(mint);
    return new BN(info!.data.readBigUInt64LE(36).toString());
  }

  async transferBase(r: Raise, from: Keypair, to: PublicKey, amount: BN) {
    const dst = r.baseAta(to);
    return this.net.send(
      "transferir tokens",
      [
        createAssociatedTokenAccountIdempotentInstruction(this.payer, dst, to, r.baseMint, TOKEN_2022_PROGRAM_ID),
        createTransferCheckedInstruction(
          r.baseAta(from.publicKey),
          r.baseMint,
          dst,
          from.publicKey,
          BigInt(amount.toString()),
          BASE_DECIMALS,
          [],
          TOKEN_2022_PROGRAM_ID,
        ),
      ],
      [from],
    );
  }
}
OWNCURVE_EOF

mkdir -p 'scripts'
cat > 'scripts/demo.ts' <<'OWNCURVE_EOF'
// F3 · Demo de punta a punta en devnet (o LiteSVM) con dos raises reales:
//
//  A "camino feliz":  lanzar → graduar → harvest → comisiones → migrar a DAMM v2 →
//                     comisiones de LP → venta de pánico → la tesorería defiende el piso
//                     (recompra bajo el respaldo y quema) → 3 tramos con evidencia al equipo
//  B "rechazo":       lanzar → graduar → harvest → el equipo propone → un holder bloquea
//                     con quórum → liquidación → el holder redime sus tokens por SOL
//
// Reanudable: guarda claves y progreso en .owncurve/demo-<cluster>.json.
// Resultado: .owncurve/demo-result-<cluster>.json y docs/DEMO-<cluster>.md (enlaces para jueces).
//
// Uso:  npx tsx scripts/demo.ts            (devnet)
//       CLUSTER=local npx tsx scripts/demo.ts
import { BN } from "@anchor-lang/core";
import { Keypair, LAMPORTS_PER_SOL, PublicKey } from "@solana/web3.js";
import fs from "fs";
import { TxError, loadIdl, makeNet } from "./lib/net";
import { DEFAULT_PARAMS, OwnCurve, Raise, RaiseParams, evidence, stateName } from "./lib/owncurve";

type Step = { name: string; sig?: string; note?: string };
type RaiseState = { config: number[]; baseMint: number[]; nftMints?: string[]; steps: Step[] };
type DemoState = { version?: number; programId: string; voter: number[]; a: RaiseState; b: RaiseState };
// v2: piso de precio + evidencia por tramo (las cuentas Raise cambiaron de tamaño)
const DEMO_VERSION = 2;
const EVIDENCE_BASE = process.env.EVIDENCE_BASE ?? "https://github.com/owncurve/owncurve";
const MILESTONES = [
  "M1 · on-chain program: treasury, tranches, objections, redemption",
  "M2 · price floor: treasury buys back below backing and burns",
  "M3 · web app + agent skill",
];

const sol = (v: BN | number | bigint) => (Number(v.toString()) / LAMPORTS_PER_SOL).toFixed(4);
const kp = (s: number[]) => Keypair.fromSecretKey(Uint8Array.from(s));
const newRaiseState = (): RaiseState => ({
  config: Array.from(Keypair.generate().secretKey),
  baseMint: Array.from(Keypair.generate().secretKey),
  steps: [],
});

async function main() {
  const net = await makeNet();
  const oc = new OwnCurve(net, loadIdl());
  const payer = net.payer.publicKey;
  const prog = await net.conn.getAccountInfo(oc.programId);
  if (!prog?.executable) throw new Error(`El programa ${oc.programId.toBase58()} no está desplegado en ${net.cluster}`);

  console.log(`\n  Red      : ${net.cluster}`);
  console.log(`  Programa : ${oc.programId.toBase58()}`);
  console.log(`  Wallet   : ${payer.toBase58()} (${sol(await net.conn.getBalance(payer))} SOL)`);

  // ---------------------------------------------------------------- estado reanudable
  const file = `.owncurve/demo-${net.cluster}.json`;
  let st: DemoState | null =
    net.cluster === "devnet" && fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, "utf8")) : null;
  if (st && (st.programId !== oc.programId.toBase58() || st.version !== DEMO_VERSION)) st = null;
  st ??= {
    version: DEMO_VERSION,
    programId: oc.programId.toBase58(),
    voter: Array.from(Keypair.generate().secretKey),
    a: newRaiseState(),
    b: newRaiseState(),
  };
  const save = () => {
    fs.mkdirSync(".owncurve", { recursive: true });
    if (net.cluster === "devnet") fs.writeFileSync(file, JSON.stringify(st, null, 2));
  };
  save();

  /** Ejecuta un paso una sola vez (aunque el script se relance) y lo registra. */
  const step = async (rs: RaiseState, name: string, fn: () => Promise<string | void>, note?: () => Promise<string>) => {
    if (rs.steps.some((s) => s.name === name)) {
      console.log(`  · ${name.padEnd(28)} (ya hecho)`);
      return;
    }
    const sig = (await fn()) || undefined;
    const n = note ? await note() : undefined;
    rs.steps.push({ name, sig, note: n });
    save();
    console.log(`  ✔ ${name.padEnd(28)} ${n ?? ""}`);
  };

  /** finalize con reintentos: el reloj de devnet puede ir unos segundos por detrás. */
  const finalizeWhenReady = async (r: Raise) => {
    for (let i = 0; i < 12; i++) {
      try {
        return await oc.finalize(r);
      } catch (e: any) {
        const text = `${e.message}\n${(e.logs ?? []).join("\n")}`;
        if (!/ChallengeWindowOpen/.test(text)) throw e;
        await net.advanceTime(5);
      }
    }
    throw new Error("La ventana de rechazo no cerró a tiempo");
  };

  // ================================================================ RAISE A
  console.log(`\n  ── Raise A · camino feliz ─────────────────────────────`);
  const pA: RaiseParams = { ...DEFAULT_PARAMS, thresholdSol: Number(process.env.THRESHOLD_A ?? 0.5) };
  const A = new Raise(oc, kp(st.a.config).publicKey, kp(st.a.baseMint).publicKey);
  await step(st.a, "A1 crear raise + config DBC", async () => (await oc.createRaise(pA, kp(st!.a.config))).sig);
  await step(st.a, "A2 lanzar pool + bind_pool", async () => (await oc.launchPool(A.config, kp(st!.a.baseMint))).sig);
  await step(st.a, "A3 comprar hasta graduar", async () => (await oc.buyToComplete(A)).at(-1), async () => {
    const c = await oc.curve(A);
    return `reserva ${sol(c.reserve)} SOL`;
  });
  await step(st.a, "A4 harvest", () => oc.harvest(A), async () => `tesorería ${sol((await A.fetch()).fundedAmount)} SOL`);
  await step(st.a, "A5 cobrar comisiones curva", () => oc.collectTradingFees(A), async () => {
    return `+${sol((await A.fetch()).feesCollected)} SOL`;
  });
  await step(st.a, "A6 migrar a DAMM v2", async () => {
    const m = await oc.migrate(A);
    st!.a.nftMints = m.nftMints.map((k) => k.toBase58());
    return m.sig;
  });
  await step(st.a, "A7 swap en DAMM v2", async () => {
    try {
      return await oc.dammBuy(A, new BN(0.02 * LAMPORTS_PER_SOL));
    } catch (e: any) {
      console.log(`    ! swap en DAMM v2 falló (${String(e.message).slice(0, 80)}); se sigue sin comisiones de LP`);
    }
  });
  await step(st.a, "A8 cobrar comisiones de LP", async () => {
    const pos = await oc.treasuryPosition(A, st!.a.nftMints!.map((s) => new PublicKey(s)));
    return oc.claimLpFees(A, pos);
  }, async () => `fees totales ${sol((await A.fetch()).feesCollected)} SOL`);

  // Piso de precio: alguien vende fuerte en DAMM v2 y el precio cae bajo el respaldo
  let floorNote = "";
  await step(st.a, "A8b venta de pánico en DAMM v2", async () => {
    const mine = await oc.tokenBalance(A.baseAta(payer));
    return oc.dammSell(A, mine.muln(6).divn(10));
  }, async () => {
    const s = await oc.dammState(A);
    const b = await oc.backing(A);
    return `precio ${(s!.price * 1e3).toPrecision(3)} vs respaldo ${(b.perUnit * 1e3).toPrecision(3)} SOL/M tokens`;
  });
  await step(st.a, "A8c defend_floor", async () => {
    const amount = await oc.suggestDefend(A);
    if (amount.isZero()) {
      floorNote = "precio ya sobre el respaldo";
      return;
    }
    const before = (await oc.backing(A)).perUnit;
    const sig = await oc.defendFloor(A, amount);
    const after = (await oc.backing(A)).perUnit;
    const raise = await A.fetch();
    const burned = Number(raise.tokensBurned.toString()) / 1e6;
    floorNote = `recompró ${sol(raise.floorSpent)} SOL, quemó ${burned.toLocaleString("en-US", { maximumFractionDigits: 0 })} tokens, respaldo +${(((after - before) / before) * 100).toFixed(0)}%`;
    return sig;
  }, async () => floorNote);
  for (let i = 1; i <= pA.tranchesBps.length; i++) {
    await step(st.a, `A9.${i} proponer tramo ${i}`, async () => {
      const raise = await A.fetch();
      const active = raise.milestones.some((m: any) => stateName(m.status) === "proposed");
      if (!active)
        return oc.propose(A, undefined, await evidence(`${EVIDENCE_BASE}/blob/main/docs/MILESTONES.md#m${i}`, MILESTONES[i - 1]));
    });
    await step(st.a, `A9.${i} esperar ventana (${pA.challengeSecs}s)`, async () => net.advanceTime(pA.challengeSecs));
    await step(st.a, `A9.${i} finalizar tramo ${i}`, () => finalizeWhenReady(A), async () => {
      const raise = await A.fetch();
      const payable = new BN(raise.fundedAmount.toString()).muln(10_000 - raise.floorReserveBps).divn(10_000);
      return `liberado ${sol(raise.releasedAmount)} / ${sol(payable)} SOL`;
    });
  }
  const finalA = await A.fetch();

  // ================================================================ RAISE B
  console.log(`\n  ── Raise B · rechazo y liquidación ─────────────────────`);
  const pB: RaiseParams = { ...DEFAULT_PARAMS, thresholdSol: Number(process.env.THRESHOLD_B ?? 0.3) };
  const B = new Raise(oc, kp(st.b.config).publicKey, kp(st.b.baseMint).publicKey);
  const voter = kp(st.voter);
  await step(st.b, "B1 crear raise + config DBC", async () => (await oc.createRaise(pB, kp(st!.b.config))).sig);
  await step(st.b, "B2 lanzar pool + bind_pool", async () => (await oc.launchPool(B.config, kp(st!.b.baseMint))).sig);
  await step(st.b, "B3 comprar hasta graduar", async () => (await oc.buyToComplete(B)).at(-1));
  await step(st.b, "B4 harvest", () => oc.harvest(B), async () => `tesorería ${sol((await B.fetch()).fundedAmount)} SOL`);
  await step(st.b, "B5 fondear al holder", () => net.fund(voter.publicKey, 0.03 * LAMPORTS_PER_SOL));
  await step(st.b, "B6 holder recibe 15% del suministro", async () => {
    const circ = (await oc.mintSupply(B.baseMint)).sub(await oc.tokenBalance(B.treasuryBase));
    return oc.transferBase(B, net.payer, voter.publicKey, circ.muln(1500).divn(10_000));
  });
  await step(st.b, "B7 equipo propone tramo 1", () => oc.propose(B));
  await step(st.b, "B8 holder vota rechazo", async () => {
    const bal = await oc.tokenBalance(B.baseAta(voter.publicKey));
    return oc.reject(B, voter, bal);
  }, async () => `bloqueados ${(await B.fetch()).proposalRejectWeight.toString()} tokens (base units)`);
  await step(st.b, `B9 esperar ventana (${pB.challengeSecs}s)`, async () => net.advanceTime(pB.challengeSecs));
  await step(st.b, "B10 finalizar → liquidación", () => finalizeWhenReady(B), async () => `estado "${await B.state()}"`);
  await step(st.b, "B11 holder retira su voto", () => oc.withdrawVote(B, voter, 0));
  let redeemPaid = new BN(0);
  await step(st.b, "B12 holder redime por SOL", async () => {
    const amount = await oc.tokenBalance(B.baseAta(voter.publicKey));
    const before = await oc.tokenBalance(B.quoteAta(voter.publicKey));
    const sig = await oc.redeem(B, voter, amount);
    redeemPaid = (await oc.tokenBalance(B.quoteAta(voter.publicKey))).sub(before);
    return sig;
  }, async () => `recibió ${sol(redeemPaid)} SOL (wSOL) por sus tokens`);
  const finalB = await B.fetch();

  // ================================================================ resumen
  const link = (s?: string) => (s ? net.explorer(s) : "");
  const addr = (a: PublicKey) =>
    net.cluster === "devnet" ? `https://explorer.solana.com/address/${a.toBase58()}?cluster=devnet` : a.toBase58();
  const result = {
    cluster: net.cluster,
    programId: oc.programId.toBase58(),
    raiseA: {
      config: A.config.toBase58(),
      treasury: A.treasury.toBase58(),
      state: stateName(finalA.state),
      fundedSol: sol(finalA.fundedAmount),
      releasedSol: sol(finalA.releasedAmount),
      payableSol: sol(new BN(finalA.fundedAmount.toString()).muln(10_000 - finalA.floorReserveBps).divn(10_000)),
      feesSol: sol(finalA.feesCollected),
      floorSpentSol: sol(finalA.floorSpent),
      tokensBurned: finalA.tokensBurned.toString(),
      treasuryNowSol: sol(await oc.tokenBalance(A.treasuryQuote)),
      steps: st.a.steps.map((s) => ({ ...s, link: link(s.sig) })),
    },
    raiseB: {
      config: B.config.toBase58(),
      treasury: B.treasury.toBase58(),
      state: stateName(finalB.state),
      fundedSol: sol(finalB.fundedAmount),
      steps: st.b.steps.map((s) => ({ ...s, link: link(s.sig) })),
    },
  };
  fs.writeFileSync(`.owncurve/demo-result-${net.cluster}.json`, JSON.stringify(result, null, 2));

  const md = [
    `# OwnCurve · demo en ${net.cluster}`,
    ``,
    `Programa: [\`${oc.programId.toBase58()}\`](${addr(oc.programId)})`,
    ``,
    `## Raise A · camino feliz`,
    ``,
    `Tesorería [\`${A.treasury.toBase58()}\`](${addr(A.treasury)}) · financiado ${result.raiseA.fundedSol} SOL · liberado al equipo en 3 tramos con evidencia ${result.raiseA.releasedSol} SOL (todo lo cobrable: ${result.raiseA.payableSol}) · comisiones cobradas ${result.raiseA.feesSol} SOL · defensa del piso ${result.raiseA.floorSpentSol} SOL · la tesorería conserva ${result.raiseA.treasuryNowSol} SOL de respaldo para los holders · estado final **${result.raiseA.state}**.`,
    ``,
    `| Paso | Resultado | Transacción |`,
    `| --- | --- | --- |`,
    ...result.raiseA.steps.filter((s) => s.sig).map((s) => `| ${s.name} | ${s.note ?? ""} | [ver](${s.link}) |`),
    ``,
    `## Raise B · rechazo y liquidación`,
    ``,
    `Tesorería [\`${B.treasury.toBase58()}\`](${addr(B.treasury)}) · financiado ${result.raiseB.fundedSol} SOL · estado final **${result.raiseB.state}**: el equipo no cobró nada y los holders redimen contra la tesorería.`,
    ``,
    `| Paso | Resultado | Transacción |`,
    `| --- | --- | --- |`,
    ...result.raiseB.steps.filter((s) => s.sig).map((s) => `| ${s.name} | ${s.note ?? ""} | [ver](${s.link}) |`),
    ``,
  ].join("\n");
  fs.mkdirSync("docs", { recursive: true });
  fs.writeFileSync(`docs/DEMO-${net.cluster}.md`, md);

  const okA = result.raiseA.state === "completed" && result.raiseA.releasedSol === result.raiseA.payableSol;
  const okB = result.raiseB.state === "liquidating";
  if (!okA || !okB) throw new Error(`Demo incompleta: A=${result.raiseA.state} B=${result.raiseB.state}`);
  console.log(`\n  DEMO OK: ciclo completo en ${net.cluster} (A completado con piso defendido, B en liquidación).`);
  console.log(`  Resumen para jueces: docs/DEMO-${net.cluster}.md`);
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error(`\n  ✘ ${e.message ?? e}`);
    if (e instanceof TxError && e.logs) {
      console.error("  Logs del programa (últimas 25 líneas):");
      for (const l of e.logs.slice(-25)) console.error("    " + l);
    }
    console.error("  Vuelve a ejecutar: el demo retoma desde el último paso completado.");
    process.exit(1);
  });
OWNCURVE_EOF

mkdir -p 'scripts'
cat > 'scripts/cli.ts' <<'OWNCURVE_EOF'
// OwnCurve CLI — the same client as the web app, with JSON output for scripts and AI agents.
//
//   npx tsx scripts/cli.ts <command> [args] [--yes]
//
// Reads never sign anything. Every command that writes is a DRY RUN unless --yes is given:
// the first transaction is simulated against the network and the result is printed.
//
// Env: RPC_URL (devnet RPC), WALLET (keypair file, default ~/.config/solana/id.json),
//      CLUSTER=local (LiteSVM, for tests).
import { BN } from "@anchor-lang/core";
import { Keypair, LAMPORTS_PER_SOL, PublicKey, Transaction, TransactionInstruction } from "@solana/web3.js";
import { Net, loadIdl, makeNet } from "./lib/net";
import { BASE_DECIMALS, DEFAULT_PARAMS, OwnCurve, Raise, evidence, stateName } from "./lib/owncurve";

const HELP = `owncurve <command> [args]   (JSON on stdout; writes need --yes, otherwise they are simulated)

Read
  list                                   every raise: state, treasury, progress
  show <config>                          one raise: tranches, proposal + evidence, price vs backing,
                                         your balance and the actions you can take now ("can")
Team
  launch --name N --symbol S [--threshold 0.5] [--treasury 80] [--tranches 30,30,40]
         [--window 60] [--quorum 10] [--floor 20]
  propose <config> --evidence URL [--note TEXT]   request the next tranche (sha256(note|URL) on-chain)
Anyone
  buy <config> --sol X                   buy on the bonding curve
  harvest <config>                       move the graduated raise into the treasury
  migrate <config>                       graduate the pool to Meteora DAMM v2
  collect-fees <config>                  curve trading fees -> treasury
  settle <config>                        pay the tranche, or open redemptions if quorum objected
  defend-floor <config> [--sol X]        treasury buys back below backing and burns (default: suggested)
Holder
  object <config> [--amount TOKENS]      lock tokens against the pending tranche (default: all)
  unlock <config>                        get voted tokens back after settlement
  redeem <config> [--amount TOKENS]      in liquidation: burn tokens for a share of the treasury
`;

type Args = { _: string[]; [k: string]: string | boolean | string[] };
function parseArgs(argv: string[]): Args {
  const out: Args = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith("--")) {
      const key = a.slice(2);
      const next = argv[i + 1];
      if (next === undefined || next.startsWith("--")) out[key] = true;
      else out[key] = argv[++i];
    } else out._.push(a);
  }
  return out;
}

const sol = (v: BN | number | bigint) => Number(v.toString()) / LAMPORTS_PER_SOL;
const tokens = (v: BN) => Number(v.toString()) / 10 ** BASE_DECIMALS;
const toTokens = (x: string) => new BN(Math.round(Number(x) * 10 ** BASE_DECIMALS).toString());
const toLamports = (x: string) => new BN(Math.round(Number(x) * LAMPORTS_PER_SOL).toString());
const DEFAULT = PublicKey.default;

class DryRun extends Error {
  constructor(public result: any) {
    super("dry-run");
  }
}

/** Net that simulates the first transaction instead of sending it. */
function dryNet(net: Net): Net {
  return {
    ...net,
    send: async (label: string, ixs: TransactionInstruction[], signers: Keypair[]) => {
      const tx = new Transaction().add(...ixs);
      tx.feePayer = net.payer.publicKey;
      tx.recentBlockhash = (await net.conn.getLatestBlockhash()).blockhash;
      const all = [net.payer, ...signers].filter((k, i, arr) => arr.findIndex((x) => x.publicKey.equals(k.publicKey)) === i);
      tx.sign(...all);
      const sim = await net.conn.simulateTransaction(tx);
      throw new DryRun({
        dryRun: true,
        transaction: label,
        wouldSucceed: !sim.value.err,
        error: sim.value.err ?? undefined,
        computeUnits: sim.value.unitsConsumed,
        logs: sim.value.err ? sim.value.logs?.slice(-12) : undefined,
        hint: "Run again with --yes to send it.",
      });
    },
  };
}

async function raiseFor(oc: OwnCurve, config: string) {
  const configKey = new PublicKey(config);
  const pda = PublicKey.findProgramAddressSync([Buffer.from("raise"), configKey.toBuffer()], oc.programId)[0];
  const raise = await (oc.program.account as any).raise.fetch(pda);
  return { r: new Raise(oc, configKey, new PublicKey(raise.baseMint)), raise };
}

async function listRaises(oc: OwnCurve) {
  const idl = loadIdl() as any;
  const disc = idl.accounts.find((a: any) => a.name === "Raise").discriminator as number[];
  const bs58 = (await import("bs58")).default;
  const raw = await oc.net.conn.getProgramAccounts(oc.programId, {
    filters: [{ memcmp: { offset: 0, bytes: bs58.encode(Uint8Array.from(disc)) } }],
  });
  const out: any[] = [];
  for (const { account } of raw) {
    let a: any;
    try {
      a = oc.program.coder.accounts.decode("raise", account.data);
    } catch {
      continue; // older program version
    }
    const config = new PublicKey(a.dbcConfig);
    const baseMint = new PublicKey(a.baseMint);
    const r = new Raise(oc, config, baseMint);
    const bound = !baseMint.equals(DEFAULT);
    out.push({
      config: config.toBase58(),
      state: stateName(a.state),
      baseMint: bound ? baseMint.toBase58() : null,
      team: new PublicKey(a.team).toBase58(),
      fundedSol: sol(a.fundedAmount),
      releasedSol: sol(a.releasedAmount),
      treasurySol: bound ? sol(await oc.tokenBalance(r.treasuryQuote)) : 0,
    });
  }
  return out;
}

async function show(oc: OwnCurve, config: string) {
  const { r, raise } = await raiseFor(oc, config);
  const state = stateName(raise.state);
  const me = oc.net.payer.publicKey;
  const bound = !r.baseMint.equals(DEFAULT);
  const funded = new BN(raise.fundedAmount.toString());
  const floorReserve = funded.muln(raise.floorReserveBps).divn(10_000);
  const payable = funded.sub(floorReserve);
  const count = Number(raise.milestoneCount);
  let acc = new BN(0);
  const milestones = (raise.milestones as any[]).slice(0, count).map((m, i) => {
    const amount = i === count - 1 ? payable.sub(acc) : payable.muln(m.trancheBps).divn(10_000);
    acc = acc.add(amount);
    return {
      index: i + 1,
      pct: m.trancheBps / 100,
      sol: sol(amount),
      status: stateName(m.status),
      evidenceSha256: m.evidenceHash.some((b: number) => b) ? Buffer.from(m.evidenceHash).toString("hex") : null,
    };
  });

  let curve: any = null;
  let market: any = null;
  let backing: any = null;
  let wallet: any = null;
  if (bound) {
    const c = await oc.curve(r).catch(() => null);
    const pool = await oc.dbc.state.getPool(r.pool).catch(() => null);
    const migrated = Boolean(pool && (pool as any).isMigrated) || Boolean(pool && (pool as any).poolState?.isMigrated);
    if (c) curve = { raisedSol: sol(c.reserve), targetSol: sol(c.threshold), complete: c.reserve.gte(c.threshold), migrated };
    const b = await oc.backing(r);
    const perM = (u: number) => (u * 10 ** BASE_DECIMALS * 1_000_000) / LAMPORTS_PER_SOL;
    backing = { treasurySol: sol(b.treasuryQuote), circulatingTokens: tokens(b.circulating), solPerMillionTokens: perM(b.perUnit) };
    if (migrated) {
      const st = await oc.dammState(r).catch(() => null);
      if (st) {
        const suggest = ["funded", "completed"].includes(state) ? await oc.suggestDefend(r) : new BN(0);
        market = {
          pool: st.pool.toBase58(),
          priceSolPerMillionTokens: perM(st.price),
          belowBacking: st.price < b.perUnit,
          suggestedDefendSol: sol(suggest),
        };
      }
    }
    const nonce = Number(raise.proposalNonce);
    const votes: { nonce: number; tokens: number }[] = [];
    for (let n = 0; n <= nonce; n++) {
      const info = await oc.net.conn.getAccountInfo(r.voteRecord(me, n));
      if (info) votes.push({ nonce: n, tokens: tokens(new BN(oc.program.coder.accounts.decode("voteRecord", info.data).amount.toString())) });
    }
    wallet = {
      address: me.toBase58(),
      sol: (await oc.net.conn.getBalance(me)) / LAMPORTS_PER_SOL,
      tokens: tokens(await oc.tokenBalance(r.baseAta(me))),
      votes,
      isTeam: me.equals(new PublicKey(raise.team)),
    };
  }

  const active = milestones.findIndex((m) => m.status === "proposed");
  const now = (await oc.net.conn.getBlockTime(await oc.net.conn.getSlot())) ?? Math.floor(Date.now() / 1000);
  const endsAt = Number(raise.proposalEndsAt.toString());
  const proposal =
    state === "funded" && active >= 0
      ? {
          tranche: active + 1,
          evidenceUri: raise.proposalEvidenceUri,
          evidenceSha256: milestones[active].evidenceSha256,
          objectionsCloseAt: new Date(endsAt * 1000).toISOString(),
          secondsLeft: Math.max(0, endsAt - now),
          objectingTokens: tokens(new BN(raise.proposalRejectWeight.toString())),
          quorumTokens: backing ? (backing.circulatingTokens * raise.rejectQuorumBps) / 10_000 : null,
        }
      : null;

  // What this wallet can do right now
  const can: string[] = [];
  if (state === "bonding" && curve && !curve.complete) can.push("buy");
  if (state === "bonding" && curve?.complete) can.push("harvest");
  if (["funded", "completed", "liquidating"].includes(state) && curve && !curve.migrated) can.push("migrate");
  if (["funded", "completed", "liquidating"].includes(state)) can.push("collect-fees");
  if (state === "funded" && !proposal && wallet?.isTeam && milestones.some((m) => m.status === "locked")) can.push("propose");
  if (proposal && proposal.secondsLeft > 0 && wallet?.tokens > 0) can.push("object");
  if (proposal && proposal.secondsLeft === 0) can.push("settle");
  if (wallet?.votes.some((v: any) => v.nonce < Number(raise.proposalNonce))) can.push("unlock");
  if (state === "liquidating" && wallet?.tokens > 0) can.push("redeem");
  if (market?.suggestedDefendSol > 0) can.push("defend-floor");

  return {
    config,
    state,
    team: new PublicKey(raise.team).toBase58(),
    baseMint: bound ? r.baseMint.toBase58() : null,
    treasury: r.treasury.toBase58(),
    rules: {
      treasuryPctMin: raise.minTreasuryPct,
      challengeWindowSecs: Number(raise.challengeWindow),
      rejectQuorumPct: raise.rejectQuorumBps / 100,
      floorReservePct: raise.floorReserveBps / 100,
    },
    fundedSol: sol(funded),
    payableToTeamSol: sol(payable),
    releasedSol: sol(raise.releasedAmount),
    feesCollectedSol: sol(raise.feesCollected),
    floor: { reserveSol: sol(floorReserve), spentSol: sol(raise.floorSpent), tokensBurned: tokens(new BN(raise.tokensBurned.toString())) },
    milestones,
    proposal,
    curve,
    backing,
    market,
    wallet,
    can,
  };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const [cmd, config] = args._;
  if (!cmd || cmd === "help" || args.help) {
    process.stdout.write(HELP);
    return;
  }
  const base = await makeNet();
  const yes = args.yes === true;
  const net = yes || ["list", "show"].includes(cmd) ? base : dryNet(base);
  const oc = new OwnCurve(net, loadIdl());
  const need = (k: string) => {
    const v = args[k];
    if (typeof v !== "string" || !v) throw new Error(`Missing --${k}`);
    return v;
  };
  const needConfig = () => {
    if (!config) throw new Error(`Usage: ${cmd} <config>`);
    return raiseFor(oc, config);
  };
  const done = (sig: string | void, extra: object = {}) => ({ ok: true, signature: sig ?? null, explorer: sig ? base.explorer(sig) : null, ...extra });

  let out: any;
  switch (cmd) {
    case "list":
      out = await listRaises(oc);
      break;
    case "show":
      if (!config) throw new Error("Usage: show <config>");
      out = await show(oc, config);
      break;
    case "launch": {
      const params = {
        ...DEFAULT_PARAMS,
        thresholdSol: Number(args.threshold ?? 0.5),
        treasuryPct: Number(args.treasury ?? 80),
        tranchesBps: String(args.tranches ?? "30,30,40").split(",").map((t) => Math.round(Number(t) * 100)),
        challengeSecs: Number(args.window ?? 60),
        quorumBps: Math.round(Number(args.quorum ?? 10) * 100),
        floorReserveBps: Math.round(Number(args.floor ?? 20) * 100),
      };
      const configKp = Keypair.generate();
      await oc.createRaise(params, configKp);
      const { sig } = await oc.launchPool(configKp.publicKey, Keypair.generate(), undefined, true, {
        name: need("name"),
        symbol: need("symbol").toUpperCase(),
        uri: String(args.uri ?? "https://raw.githubusercontent.com/solana-developers/opos-asset/main/assets/DeveloperPortal/metadata.json"),
      });
      out = done(sig, { config: configKp.publicKey.toBase58() });
      break;
    }
    case "buy": {
      const { r } = await needConfig();
      out = done(await oc.buy(r, toLamports(need("sol"))));
      break;
    }
    case "harvest": {
      const { r } = await needConfig();
      out = done(await oc.harvest(r));
      break;
    }
    case "migrate": {
      const { r } = await needConfig();
      out = done((await oc.migrate(r)).sig);
      break;
    }
    case "collect-fees": {
      const { r } = await needConfig();
      out = done(await oc.collectTradingFees(r));
      break;
    }
    case "propose": {
      const { r } = await needConfig();
      const ev = await evidence(need("evidence"), typeof args.note === "string" ? args.note : undefined);
      out = done(await oc.propose(r, undefined, ev), { evidenceUri: ev.uri, evidenceSha256: Buffer.from(ev.hash).toString("hex") });
      break;
    }
    case "object": {
      const { r } = await needConfig();
      const amount = typeof args.amount === "string" ? toTokens(args.amount) : await oc.tokenBalance(r.baseAta(base.payer.publicKey));
      out = done(await oc.reject(r, base.payer, amount), { tokens: tokens(amount) });
      break;
    }
    case "settle": {
      const { r } = await needConfig();
      out = done(await oc.finalize(r));
      break;
    }
    case "unlock": {
      const { r, raise } = await needConfig();
      let sig: string | void = undefined;
      for (let n = 0; n < Number(raise.proposalNonce); n++) {
        if (await base.conn.getAccountInfo(r.voteRecord(base.payer.publicKey, n))) sig = await oc.withdrawVote(r, base.payer, n);
      }
      out = done(sig);
      break;
    }
    case "redeem": {
      const { r } = await needConfig();
      const amount = typeof args.amount === "string" ? toTokens(args.amount) : await oc.tokenBalance(r.baseAta(base.payer.publicKey));
      out = done(await oc.redeem(r, base.payer, amount), { tokens: tokens(amount) });
      break;
    }
    case "defend-floor": {
      const { r } = await needConfig();
      const amount = typeof args.sol === "string" ? toLamports(args.sol) : await oc.suggestDefend(r);
      if (amount.isZero()) {
        out = { ok: false, reason: "The market price is not below the treasury backing (or the floor budget is empty)." };
        break;
      }
      out = done(await oc.defendFloor(r, amount), { spentSol: sol(amount) });
      break;
    }
    default:
      throw new Error(`Unknown command "${cmd}". Run: owncurve help`);
  }
  console.log(JSON.stringify(out, null, 2));
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    if (e instanceof DryRun) {
      console.log(JSON.stringify(e.result, null, 2));
      process.exit(0);
    }
    const logs: string[] = e?.logs ?? [];
    const named = logs.join("\n").match(/Error Code: (\w+)/)?.[1];
    console.log(JSON.stringify({ ok: false, error: named ?? String(e?.message ?? e).slice(0, 300) }, null, 2));
    process.exit(1);
  });
OWNCURVE_EOF

mkdir -p 'skills/owncurve'
cat > 'skills/owncurve/SKILL.md' <<'OWNCURVE_EOF'
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
git clone https://github.com/owncurve/owncurve && cd owncurve && npm ci
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
OWNCURVE_EOF

mkdir -p 'docs'
cat > 'docs/MILESTONES.md' <<'OWNCURVE_EOF'
# OwnCurve milestones

Each tranche request (`propose_release`) points here and commits the SHA-256 of the
milestone line below, so holders can check what the team claimed before the challenge
window closes.

## m1

M1 · on-chain program: treasury, tranches, objections, redemption

## m2

M2 · price floor: treasury buys back below backing and burns

## m3

M3 · web app + agent skill
OWNCURVE_EOF

mkdir -p '.github/workflows'
cat > '.github/workflows/pages.yml' <<'OWNCURVE_EOF'
# Public demo: builds the web app against Solana devnet and publishes it on GitHub Pages.
# Settings → Pages → Source: "GitHub Actions". Optional repo variable VITE_RPC_URL
# (a public devnet RPC with CORS); never put a paid RPC key here, the build is public.
name: pages
on:
  push:
    branches: [main]
  workflow_dispatch:
permissions:
  contents: read
  pages: write
  id-token: write
concurrency:
  group: pages
  cancel-in-progress: true
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: npm
      - run: npm ci --no-audit --no-fund
      - run: npx vite build --config app/vite.config.ts
        env:
          VITE_CLUSTER: devnet
          VITE_RPC_URL: ${{ vars.VITE_RPC_URL || 'https://api.devnet.solana.com' }}
      - uses: actions/upload-pages-artifact@v3
        with:
          path: app/dist
  deploy:
    needs: build
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - id: deployment
        uses: actions/deploy-pages@v4
OWNCURVE_EOF

mkdir -p 'tests'
cat > 'tests/owncurve.test.ts' <<'OWNCURVE_EOF'
// F2 · Tests de integración de OwnCurve contra los binarios reales de Meteora (DBC + DAMM v2)
// en LiteSVM. Cada test arranca un validador limpio.
//
// Ejecutar:  CLUSTER=local npx tsx --test tests/owncurve.test.ts
import { BN } from "@anchor-lang/core";
import { SwapMode } from "@meteora-ag/dynamic-bonding-curve-sdk";
import { Keypair, LAMPORTS_PER_SOL } from "@solana/web3.js";
import assert from "node:assert/strict";
import { test } from "node:test";
import { loadIdl, makeNet } from "../scripts/lib/net";
import { DEFAULT_PARAMS, OwnCurve, Raise, RaiseParams, evidence, sha256, stateName } from "../scripts/lib/owncurve";

process.env.CLUSTER = "local";

// ------------------------------------------------------------------ utilidades
async function setup(params: Partial<RaiseParams> = {}) {
  const net = await makeNet();
  const oc = new OwnCurve(net, loadIdl());
  return { net, oc, p: { ...DEFAULT_PARAMS, ...params } };
}

/** Raise lanzado y validado (estado "bonding"). */
async function bondingRaise(params: Partial<RaiseParams> = {}) {
  const s = await setup(params);
  const { configKp } = await s.oc.createRaise(s.p);
  const { raise: r } = await s.oc.launchPool(configKp.publicKey);
  return { ...s, r };
}

/** Raise con la curva completa y el migration fee ya en la tesorería (estado "funded"). */
async function fundedRaise(params: Partial<RaiseParams> = {}) {
  const s = await bondingRaise(params);
  await s.oc.buyToComplete(s.r);
  await s.oc.harvest(s.r);
  return s;
}

async function expectError(p: Promise<unknown>, name: string) {
  try {
    await p;
  } catch (e: any) {
    const text = `${e.message}\n${(e.logs ?? []).join("\n")}`;
    assert.match(text, new RegExp(name), `se esperaba ${name}, llegó:\n${text.slice(-600)}`);
    return;
  }
  assert.fail(`se esperaba el error ${name} y la transacción pasó`);
}

const raiseOf = (r: Raise) => r.fetch();
const n = (v: any) => new BN(v.toString());

/** Tokens con derecho sobre la tesorería, igual que el programa: suministro − tokens de la tesorería. */
async function circulating(oc: OwnCurve, r: Raise) {
  return (await oc.mintSupply(r.baseMint)).sub(await oc.tokenBalance(r.treasuryBase));
}

// ------------------------------------------------------------------ flujo feliz
test("2.4 flujo feliz: la tesorería se financia y los 3 tramos se liberan al equipo (menos la reserva del piso)", async () => {
  const { oc, net, r, p } = await fundedRaise();
  const fundedAll = n((await raiseOf(r)).fundedAmount);
  assert.ok(fundedAll.eq(new BN(p.thresholdSol * LAMPORTS_PER_SOL).muln(p.treasuryPct).divn(100)), "80% del umbral");
  const reserve = fundedAll.muln(p.floorReserveBps).divn(10_000);
  const funded = fundedAll.sub(reserve); // lo que el equipo puede cobrar en tramos

  const teamQuote = r.quoteAta(net.payer.publicKey);
  let paid = new BN(0);
  for (let i = 0; i < p.tranchesBps.length; i++) {
    await oc.propose(r);
    await net.advanceTime(p.challengeSecs + 1);
    const before = await oc.tokenBalance(teamQuote);
    await oc.finalize(r);
    const got = (await oc.tokenBalance(teamQuote)).sub(before);
    const isLast = i === p.tranchesBps.length - 1;
    const expected = isLast ? funded.sub(paid) : funded.muln(p.tranchesBps[i]).divn(10_000);
    assert.ok(got.eq(expected), `tramo ${i + 1}: recibido ${got} esperado ${expected}`);
    paid = paid.add(got);
  }
  const raise = await raiseOf(r);
  assert.equal(stateName(raise.state), "completed");
  assert.ok(n(raise.releasedAmount).eq(funded), "todo lo cobrable fue liberado, ni un lamport más");
  assert.ok((await oc.tokenBalance(r.treasuryQuote)).gte(reserve), "la reserva del piso sigue en la tesorería");
});

// ------------------------------------------------------------------ hitos con evidencia
test("2.7 cada tramo se pide con evidencia: el enlace y su hash quedan en cadena", async () => {
  const { oc, r } = await fundedRaise();
  const ev = await evidence("https://github.com/acme/app/releases/tag/v0.1", "commit 4f2a9c1: beta shipped");
  await oc.propose(r, undefined, ev);
  const raise = await raiseOf(r);
  assert.equal(raise.proposalEvidenceUri, ev.uri);
  assert.deepEqual(Array.from(raise.milestones[0].evidenceHash), await sha256("commit 4f2a9c1: beta shipped"));
});

test("2.7 propose_release sin evidencia falla", async () => {
  const { oc, r } = await fundedRaise();
  await expectError(oc.propose(r, undefined, { uri: "  ", hash: new Array(32).fill(0) }), "InvalidEvidence");
  await expectError(oc.propose(r, undefined, { uri: "https://x.io/" + "a".repeat(200), hash: new Array(32).fill(0) }), "InvalidEvidence");
});

// ------------------------------------------------------------------ piso de precio
/** Raise graduado en DAMM v2 cuyo precio de mercado cae por debajo del respaldo de la tesorería. */
async function crashedRaise() {
  const s = await fundedRaise();
  await s.oc.migrate(s.r);
  const mine = await s.oc.tokenBalance(s.r.baseAta(s.net.payer.publicKey));
  await s.oc.dammSell(s.r, mine.muln(6).divn(10)); // venta de pánico: 60% de lo que tiene el equipo
  return s;
}

test("2.8 defend_floor: con el precio por debajo del respaldo, la tesorería recompra y quema", async () => {
  const { oc, r } = await crashedRaise();
  const st = await oc.dammState(r);
  const before = await oc.backing(r);
  assert.ok(st!.price < before.perUnit, `precio ${st!.price} < respaldo ${before.perUnit}`);
  const amount = await oc.suggestDefend(r);
  assert.ok(amount.gtn(0), "hay algo que defender");
  const supply = await oc.mintSupply(r.baseMint);
  await oc.defendFloor(r, amount);
  const raise = await raiseOf(r);
  const burned = n(raise.tokensBurned);
  assert.ok(n(raise.floorSpent).eq(amount), "floor_spent registra lo gastado");
  assert.ok(burned.gtn(0) && (await oc.mintSupply(r.baseMint)).eq(supply.sub(burned)), "lo recomprado se quema");
  const after = await oc.backing(r);
  assert.ok(after.perUnit > before.perUnit, `el respaldo por token sube: ${before.perUnit} → ${after.perUnit}`);
  assert.ok((await oc.dammState(r))!.price > st!.price, "el precio de mercado sube");
});

test("2.8 defend_floor no recompra por encima del respaldo", async () => {
  const { oc, r } = await fundedRaise();
  await oc.migrate(r);
  const st = await oc.dammState(r);
  const b = await oc.backing(r);
  if (st!.price >= b.perUnit) {
    await expectError(oc.defendFloor(r, new BN(1_000_000)), "Slippage|NothingToDefend|0x");
  } else {
    // si el precio de graduación ya estuviera por debajo, una compra grande lo cruzaría
    await expectError(oc.defendFloor(r, await oc.floorBudget(r)), "Slippage|NothingToDefend|0x");
  }
});

test("2.8 defend_floor no puede gastar más que su presupuesto (reserva + comisiones)", async () => {
  const { oc, r } = await crashedRaise();
  const budget = await oc.floorBudget(r);
  await expectError(oc.defendFloor(r, budget.addn(1)), "FloorBudgetExceeded");
});

test("2.8 init_raise limita la reserva del piso a ≤ 50%", async () => {
  const s = await setup({ floorReserveBps: 5001 });
  await expectError(s.oc.createRaise(s.p), "InvalidGovernance");
});

test("2.1 comisiones de trading de la curva van a la tesorería", async () => {
  const { oc, r } = await fundedRaise();
  const before = await oc.tokenBalance(r.treasuryQuote);
  await oc.collectTradingFees(r);
  const delta = (await oc.tokenBalance(r.treasuryQuote)).sub(before);
  const raise = await raiseOf(r);
  assert.ok(delta.gtn(0), "la tesorería recibió comisiones");
  assert.ok(n(raise.feesCollected).eq(delta), "fees_collected registra lo cobrado");
});

test("2.1 excedente: la curva no deja pasarse del umbral; collect_surplus cobra lo que haya, una sola vez", async () => {
  const { oc, r } = await bondingRaise();
  const c0 = await oc.curve(r);
  await oc.buy(r, c0.threshold.muln(9).divn(10)); // ~90% de la curva
  const c1 = await oc.curve(r);
  // Una compra exacta que rebasaría el umbral se rechaza: el precio no puede pasar el de graduación.
  await expectError(
    oc.buy(r, c1.threshold.sub(c1.reserve).add(c0.threshold.divn(20)), undefined, SwapMode.ExactIn),
    "Insufficient Liquidity|InsufficientLiquidity",
  );
  await oc.buyToComplete(r);
  await oc.harvest(r);
  const before = await oc.tokenBalance(r.treasuryQuote);
  await oc.collectSurplus(r);
  const delta = (await oc.tokenBalance(r.treasuryQuote)).sub(before);
  assert.ok(delta.gten(0));
  assert.ok(n((await raiseOf(r)).feesCollected).eq(delta), "fees_collected registra el excedente (0 con esta curva)");
  await expectError(oc.collectSurplus(r), "SurplusHasBeenWithdraw");
});

test("2.1 tras migrar a DAMM v2, la tesorería cobra las comisiones de su posición de LP", async () => {
  const { oc, r } = await fundedRaise();
  const { nftMints } = await oc.migrate(r);
  const pos = await oc.treasuryPosition(r, nftMints);
  await oc.dammBuy(r, new BN(0.2 * LAMPORTS_PER_SOL));
  const before = await oc.tokenBalance(r.treasuryQuote);
  await oc.claimLpFees(r, pos);
  const delta = (await oc.tokenBalance(r.treasuryQuote)).sub(before);
  assert.ok(delta.gtn(0), "comisiones de LP en SOL para la tesorería");
  assert.ok(n((await raiseOf(r)).feesCollected).eq(delta));
});

// ------------------------------------------------------------------ rechazo y liquidación
test("2.5 rechazo con quórum → liquidación → redención proporcional al NAV", async () => {
  const { oc, net, r, p } = await fundedRaise();
  const voter = Keypair.generate();
  await net.fund(voter.publicKey, LAMPORTS_PER_SOL);
  const circ = await circulating(oc, r);
  const stake = circ.muln(p.quorumBps + 500).divn(10_000); // quórum + 5%
  await oc.transferBase(r, net.payer, voter.publicKey, stake);

  await oc.propose(r);
  const nonce = (await raiseOf(r)).proposalNonce;
  await oc.reject(r, voter, stake);
  assert.ok((await oc.tokenBalance(r.baseAta(voter.publicKey))).isZero(), "tokens bloqueados en escrow");
  await net.advanceTime(p.challengeSecs + 1);
  await oc.finalize(r);
  assert.equal(stateName((await raiseOf(r)).state), "liquidating");
  assert.ok((await oc.tokenBalance(r.quoteAta(net.payer.publicKey))).isZero(), "el equipo no cobró nada");

  await oc.withdrawVote(r, voter, nonce);
  assert.ok((await oc.tokenBalance(r.baseAta(voter.publicKey))).eq(stake), "votos devueltos");

  const tq = await oc.tokenBalance(r.treasuryQuote);
  const c2 = await circulating(oc, r);
  const expected = stake.mul(tq).div(c2);
  const supplyBefore = await oc.mintSupply(r.baseMint);
  await oc.redeem(r, voter, stake);
  assert.ok((await oc.tokenBalance(r.quoteAta(voter.publicKey))).eq(expected), "pago = tokens × NAV / circulante");
  assert.ok((await oc.mintSupply(r.baseMint)).eq(supplyBefore.sub(stake)), "los tokens se queman");
});

test("2.5 un rechazo por debajo del quórum no bloquea el tramo", async () => {
  const { oc, net, r, p } = await fundedRaise();
  const voter = Keypair.generate();
  await net.fund(voter.publicKey, LAMPORTS_PER_SOL);
  const stake = (await circulating(oc, r)).muln(p.quorumBps - 200).divn(10_000);
  await oc.transferBase(r, net.payer, voter.publicKey, stake);
  await oc.propose(r);
  await oc.reject(r, voter, stake);
  await net.advanceTime(p.challengeSecs + 1);
  await oc.finalize(r);
  const raise = await raiseOf(r);
  assert.equal(stateName(raise.state), "funded");
  assert.ok(n(raise.releasedAmount).gtn(0), "el tramo 1 se liberó");
});

// ------------------------------------------------------------------ seguridad
test("2.6 bind_pool rechaza una config DBC cuyo fee_claimer no es la tesorería", async () => {
  const s = await setup();
  const { configKp } = await s.oc.createRaise({ ...s.p, feeClaimer: s.net.payer.publicKey });
  await expectError(s.oc.launchPool(configKp.publicKey), "FeeClaimerNotTreasury");
});

test("2.6 bind_pool rechaza una config que comparte el migration fee con el creador", async () => {
  const s = await setup();
  const { configKp } = await s.oc.createRaise({ ...s.p, creatorMigrationFeePct: 10 });
  await expectError(s.oc.launchPool(configKp.publicKey), "CreatorMigrationFeeNotZero");
});

test("2.6 bind_pool rechaza una config que deja LP desbloqueado al creador (rug de liquidez)", async () => {
  const s = await setup();
  const { configKp } = await s.oc.createRaise({ ...s.p, creatorUnlockedLpPct: 20 });
  await expectError(s.oc.launchPool(configKp.publicKey), "CreatorLpNotLocked");
});

test("2.6 init_raise impone límites de gobernanza: ventana ≥ 60 s, quórum ≤ 30%, tesorería ≥ 50%", async () => {
  const s = await setup();
  await expectError(s.oc.createRaise({ ...s.p, challengeSecs: 5 }), "InvalidGovernance");
  await expectError(s.oc.createRaise({ ...s.p, quorumBps: 5000 }), "InvalidGovernance");
  await expectError(s.oc.createRaise({ ...s.p, treasuryPct: 40 }), "InvalidGovernance");
});

test("2.6 nadie fuera del programa puede retirar el migration fee de DBC", async () => {
  const { oc, net, r } = await bondingRaise();
  await oc.buyToComplete(r);
  const attacker = Keypair.generate();
  await net.fund(attacker.publicKey, LAMPORTS_PER_SOL);
  const tx = await oc.dbc.partner.partnerWithdrawMigrationFee({ pool: r.pool, sender: attacker.publicKey });
  await expectError(net.send("ataque", tx.instructions, [attacker]), "NotPermitToDoThisAction");
  await oc.harvest(r); // el camino legítimo sigue funcionando
  assert.equal(stateName((await raiseOf(r)).state), "funded");
});

test("2.6 harvest no se puede ejecutar dos veces", async () => {
  const { oc, r } = await fundedRaise();
  await expectError(oc.harvest(r), "InvalidState");
});

test("2.6 harvest antes de completar la curva falla en DBC", async () => {
  const { oc, r } = await bondingRaise();
  await expectError(oc.harvest(r), "NotPermitToDoThisAction");
});

test("2.6 solo el equipo puede proponer un tramo", async () => {
  const { oc, net, r } = await fundedRaise();
  const attacker = Keypair.generate();
  await net.fund(attacker.publicKey, LAMPORTS_PER_SOL);
  await expectError(oc.propose(r, attacker), "NotTeam");
});

test("2.6 ventanas: no se finaliza antes de tiempo ni se vota fuera de plazo", async () => {
  const { oc, net, r, p } = await fundedRaise();
  await oc.propose(r);
  await expectError(oc.finalize(r), "ChallengeWindowOpen");
  await net.advanceTime(p.challengeSecs + 1);
  await expectError(oc.reject(r, net.payer, new BN(1_000_000)), "ChallengeWindowClosed");
});

test("2.6 no se puede redimir si el raise no está en liquidación", async () => {
  const { oc, net, r } = await fundedRaise();
  await expectError(oc.redeem(r, net.payer, new BN(1_000_000)), "InvalidState");
});

test("2.6 init_raise rechaza tramos que no suman 100%", async () => {
  const s = await setup();
  await expectError(s.oc.createRaise({ ...s.p, tranchesBps: [5000, 4000] }), "InvalidMilestones");
});
OWNCURVE_EOF

mkdir -p 'tests'
cat > 'tests/cli.test.ts' <<'OWNCURVE_EOF'
// Test del CLI (lo que usa la Agent Skill): cada comando es un proceso aparte que habla
// por JSON-RPC con un validador LiteSVM (el mismo servidor que el test E2E de la interfaz).
//
// Ejecutar:  npx tsx --test tests/cli.test.ts
import { Keypair } from "@solana/web3.js";
import { execFile } from "child_process";
import fs from "fs";
import os from "os";
import path from "path";
import assert from "node:assert/strict";
import { after, before, test } from "node:test";
import { promisify } from "util";
import { startRpc } from "./e2e/rpc-server";

const run = promisify(execFile);
let rpc: Awaited<ReturnType<typeof startRpc>>;
const team = Keypair.generate();
const holder = Keypair.generate();
const dir = fs.mkdtempSync(path.join(os.tmpdir(), "owncurve-cli-"));
const wallet = (k: Keypair, name: string) => {
  const f = path.join(dir, `${name}.json`);
  fs.writeFileSync(f, JSON.stringify(Array.from(k.secretKey)));
  return f;
};

async function cli(who: Keypair, ...args: string[]) {
  const env = { ...process.env, CLUSTER: "devnet", RPC_URL: rpc.url, WALLET: wallet(who, who === team ? "team" : "holder") };
  try {
    const { stdout } = await run("npx", ["tsx", "scripts/cli.ts", ...args], { env, maxBuffer: 1 << 24 });
    return JSON.parse(stdout);
  } catch (e: any) {
    return JSON.parse(e.stdout || `{"ok":false,"error":${JSON.stringify(String(e.stderr || e.message))}}`);
  }
}
const yes = async (p: Promise<any>) => {
  const r = await p;
  assert.equal(r.ok, true, JSON.stringify(r));
  return r;
};
const warp = (secs: number) =>
  fetch(rpc.url, { method: "POST", body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "owncurve_warp", params: [secs] }) });

before(async () => {
  rpc = await startRpc(8898);
  rpc.svm.airdrop(team.publicKey, 10_000_000_000n);
  rpc.svm.airdrop(holder.publicKey, 2_000_000_000n);
});
after(() => rpc.server.close());

test("la Agent Skill puede llevar un raise de punta a punta solo con el CLI", { timeout: 600_000 }, async () => {
  // Escribir sin --yes solo simula
  const dry = await cli(team, "launch", "--name", "Agent Labs", "--symbol", "agnt");
  assert.equal(dry.dryRun, true, JSON.stringify(dry));
  assert.equal(dry.wouldSucceed, true, JSON.stringify(dry));
  assert.deepEqual(await cli(team, "list"), [], "la simulación no creó nada");

  const launched = await cli(team, "launch", "--name", "Agent Labs", "--symbol", "agnt", "--threshold", "0.5", "--yes");
  assert.equal(launched.ok, true, JSON.stringify(launched));
  const config = launched.config;
  let s = await cli(team, "show", config);
  assert.equal(s.state, "bonding");
  assert.ok(s.can.includes("buy"));
  assert.equal(s.rules.floorReservePct, 20);

  await yes(cli(team, "buy", config, "--sol", "0.3", "--yes"));
  await yes(cli(holder, "buy", config, "--sol", "0.002", "--yes"));
  await yes(cli(team, "buy", config, "--sol", "1", "--yes"));
  s = await cli(team, "show", config);
  assert.ok(s.curve.complete && s.can.includes("harvest"), JSON.stringify(s.curve));
  await yes(cli(team, "harvest", config, "--yes"));

  // propose con evidencia: el hash queda en cadena y show lo devuelve
  const p = await cli(team, "propose", config, "--evidence", "https://example.com/m1", "--note", "M1 shipped", "--yes");
  assert.equal(p.ok, true, JSON.stringify(p));
  s = await cli(holder, "show", config);
  assert.equal(s.proposal.evidenceUri, "https://example.com/m1");
  assert.equal(s.proposal.evidenceSha256, p.evidenceSha256);
  assert.ok(s.can.includes("object"));

  // el holder objeta (no llega al quórum: el equipo tiene casi todo), se liquida el tramo
  await yes(cli(holder, "object", config, "--yes"));
  await warp(61);
  await yes(cli(holder, "settle", config, "--yes"));
  s = await cli(holder, "show", config);
  assert.equal(s.state, "funded", "la objeción no llegó al quórum");
  assert.equal(s.milestones[0].status, "released");
  assert.ok(s.can.includes("unlock"));
  await yes(cli(holder, "unlock", config, "--yes"));

  // errores del programa salen como JSON con el nombre del error
  const bad = await cli(holder, "propose", config, "--evidence", "https://example.com/x", "--yes");
  assert.equal(bad.ok, false);
  assert.match(bad.error, /NotTeam/);

  // piso: graduar, y defend-floor sin nada que defender lo explica
  await yes(cli(team, "migrate", config, "--yes"));
  s = await cli(team, "show", config);
  assert.ok(s.market && typeof s.market.priceSolPerMillionTokens === "number", JSON.stringify(s.market));
  assert.equal(s.market.belowBacking, false);
  assert.equal((await cli(team, "defend-floor", config, "--yes")).ok, false);
});
OWNCURVE_EOF

mkdir -p 'tests/e2e'
cat > 'tests/e2e/rpc-server.ts' <<'OWNCURVE_EOF'
// Servidor JSON-RPC mínimo sobre LiteSVM (con los .so reales de DBC, DAMM v2 y OwnCurve).
// Implementa lo que usan web3.js, Anchor y el SDK de Meteora desde el navegador, más un
// método propio `owncurve_warp` para adelantar el reloj en los tests de la interfaz.
import { PublicKey, Transaction, VersionedTransaction } from "@solana/web3.js";
import bs58 from "bs58";
import http from "http";
import { makeNet } from "../../scripts/lib/net";

export async function startRpc(port = 8899) {
  process.env.CLUSTER = "local";
  const net = await makeNet();
  const svm = net.svm;
  const known = new Set<string>(); // LiteSVM no enumera cuentas: recordamos las que aparecen
  const statuses = new Map<string, { slot: number; err: any }>();
  const remember = (k: PublicKey | string) => known.add(typeof k === "string" ? k : k.toBase58());

  const slot = () => Number(svm.getClock().slot);
  const ctx = () => ({ slot: slot(), apiVersion: "3.1.14" });
  const acct = (pk: PublicKey) => {
    const a = svm.getAccount(pk);
    if (!a || (Number(a.lamports) === 0 && a.data.length === 0)) return null;
    return {
      data: [Buffer.from(a.data).toString("base64"), "base64"],
      executable: a.executable,
      lamports: Number(a.lamports),
      owner: new PublicKey(a.owner).toBase58(),
      rentEpoch: 0,
      space: a.data.length,
    };
  };
  const fakeSig = () => bs58.encode(Buffer.from(Array.from({ length: 64 }, () => Math.floor(Math.random() * 256))));
  const advance = () => {
    const c = svm.getClock();
    c.slot = c.slot + 1n;
    c.unixTimestamp = c.unixTimestamp + 1n;
    svm.setClock(c);
  };

  const methods: Record<string, (p: any[]) => any> = {
    getVersion: () => ({ "solana-core": "3.1.14", "feature-set": 0 }),
    getGenesisHash: () => "EtWTRABZaYq6iMfeYKouRu166VU2xqa1wcaWoxPkrZBG",
    getSlot: () => slot(),
    getBlockHeight: () => slot(),
    getEpochInfo: () => ({ absoluteSlot: slot(), blockHeight: slot(), epoch: 0, slotIndex: slot(), slotsInEpoch: 432000 }),
    getBlockTime: () => Number(svm.getClock().unixTimestamp),
    getLatestBlockhash: () => ({ context: ctx(), value: { blockhash: svm.latestBlockhash(), lastValidBlockHeight: slot() + 150 } }),
    getMinimumBalanceForRentExemption: ([n]) => Number(svm.minimumBalanceForRentExemption(BigInt(n))),
    getBalance: ([pk]) => ({ context: ctx(), value: Number(svm.getBalance(new PublicKey(pk)) ?? 0n) }),
    getAccountInfo: ([pk]) => {
      remember(pk);
      return { context: ctx(), value: acct(new PublicKey(pk)) };
    },
    getMultipleAccounts: ([pks]) => ({ context: ctx(), value: pks.map((k: string) => (remember(k), acct(new PublicKey(k)))) }),
    getTokenAccountBalance: ([pk]) => {
      const a = svm.getAccount(new PublicKey(pk));
      const amount = a && a.data.length >= 72 ? Buffer.from(a.data).readBigUInt64LE(64) : 0n;
      return { context: ctx(), value: { amount: amount.toString(), decimals: 9, uiAmount: Number(amount) / 1e9, uiAmountString: "" } };
    },
    getProgramAccounts: ([program, cfg]) => {
      const owner = new PublicKey(program);
      const out: any[] = [];
      for (const k of known) {
        const pk = new PublicKey(k);
        const a = svm.getAccount(pk);
        if (!a || !new PublicKey(a.owner).equals(owner)) continue;
        const data = Buffer.from(a.data);
        const ok = (cfg?.filters ?? []).every((f: any) => {
          if (f.dataSize !== undefined) return data.length === f.dataSize;
          if (f.memcmp) {
            const want = f.memcmp.encoding === "base64" ? Buffer.from(f.memcmp.bytes, "base64") : Buffer.from(bs58.decode(f.memcmp.bytes));
            return data.subarray(f.memcmp.offset, f.memcmp.offset + want.length).equals(want);
          }
          return true;
        });
        if (ok) out.push({ pubkey: k, account: acct(pk) });
      }
      return cfg?.withContext ? { context: ctx(), value: out } : out;
    },
    getSignatureStatuses: ([sigs]) => ({
      context: ctx(),
      value: sigs.map((s: string) => {
        const st = statuses.get(s);
        return st ? { slot: st.slot, confirmations: null, err: st.err, confirmationStatus: "confirmed", status: st.err ? { Err: st.err } : { Ok: null } } : null;
      }),
    }),
    requestAirdrop: ([pk, lamports]) => {
      remember(pk);
      svm.airdrop(new PublicKey(pk), BigInt(lamports));
      const sig = fakeSig();
      statuses.set(sig, { slot: slot(), err: null });
      return sig;
    },
    sendTransaction: ([b64]) => {
      const raw = Buffer.from(b64, "base64");
      let tx: Transaction | VersionedTransaction;
      let keys: PublicKey[];
      try {
        tx = Transaction.from(raw);
        keys = tx.compileMessage().accountKeys;
      } catch {
        tx = VersionedTransaction.deserialize(raw);
        keys = tx.message.staticAccountKeys;
      }
      keys.forEach(remember);
      const res: any = svm.sendTransaction(tx as any);
      svm.expireBlockhash();
      advance();
      if (res.constructor.name === "FailedTransactionMetadata" || typeof res.err === "function") {
        const logs: string[] = res.meta().logs();
        const err = { message: "Transaction simulation failed: " + res.err().toString(), logs };
        throw Object.assign(new Error(err.message), { rpc: { code: -32002, message: err.message, data: { err: res.err().toString(), logs, accounts: null, unitsConsumed: 0 } } });
      }
      const sig = bs58.encode((tx as any).signature ?? (tx as any).signatures[0]);
      statuses.set(sig, { slot: slot(), err: null });
      return sig;
    },
    simulateTransaction: ([b64, cfg]) => {
      const raw = Buffer.from(b64, cfg?.encoding === "base58" ? "base64" : "base64");
      let tx: Transaction | VersionedTransaction;
      try {
        tx = Transaction.from(raw);
        tx.compileMessage().accountKeys.forEach(remember);
      } catch {
        tx = VersionedTransaction.deserialize(raw);
        tx.message.staticAccountKeys.forEach(remember);
      }
      const res: any = svm.simulateTransaction(tx as any);
      const failed = res.constructor.name === "FailedTransactionMetadata" || typeof res.err === "function";
      const meta = failed ? res.meta() : res.meta();
      return {
        context: ctx(),
        value: {
          err: failed ? res.err().toString() : null,
          logs: meta.logs(),
          unitsConsumed: Number(meta.computeUnitsConsumed()),
          accounts: null,
          returnData: null,
        },
      };
    },
    // Solo para tests: adelanta el reloj de la cadena.
    owncurve_warp: ([secs]) => {
      const c = svm.getClock();
      c.unixTimestamp = c.unixTimestamp + BigInt(secs);
      c.slot = c.slot + BigInt(Math.ceil(secs * 2.5));
      svm.setClock(c);
      return Number(c.unixTimestamp);
    },
    owncurve_airdrop: ([pk, lamports]) => {
      remember(pk);
      svm.airdrop(new PublicKey(pk), BigInt(lamports));
      return true;
    },
  };

  const server = http.createServer((req, res) => {
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Headers", "*");
    res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
    if (req.method === "OPTIONS") return res.end();
    let body = "";
    req.on("data", (c) => (body += c));
    req.on("end", () => {
      const reqs = JSON.parse(body);
      const one = (r: any) => {
        const fn = methods[r.method];
        if (!fn) return { jsonrpc: "2.0", id: r.id, error: { code: -32601, message: `Method not found: ${r.method}` } };
        try {
          return { jsonrpc: "2.0", id: r.id, result: fn(r.params ?? []) };
        } catch (e: any) {
          return { jsonrpc: "2.0", id: r.id, error: e.rpc ?? { code: -32000, message: String(e.message ?? e) } };
        }
      };
      res.setHeader("Content-Type", "application/json");
      res.end(JSON.stringify(Array.isArray(reqs) ? reqs.map(one) : one(reqs)));
    });
  });
  await new Promise<void>((r) => server.listen(port, "127.0.0.1", () => r()));
  return { server, svm, net, url: `http://127.0.0.1:${port}` };
}

if (require.main === module) {
  startRpc().then(({ url }) => console.log(`LiteSVM RPC listo en ${url}`));
}
OWNCURVE_EOF

mkdir -p 'tests/e2e'
cat > 'tests/e2e/ui.e2e.ts' <<'OWNCURVE_EOF'
// Test E2E de la interfaz: navegador real (Chromium) + app (Vite) + LiteSVM con los
// programas reales. Dos personas con wallets de prueba: el equipo y un holder.
//
//  equipo lanza un raise → holder compra → equipo completa la curva → tesorería financiada →
//  graduación a DAMM v2 → venta de pánico → cualquiera dispara la defensa del piso →
//  equipo pide el tramo 1 con evidencia → holder la ve y objeta con quórum → se cierra la ventana → liquidación →
//  holder desbloquea sus tokens y los redime por SOL
//
// Ejecutar: npx tsx tests/e2e/ui.e2e.ts   (SHOTS=dir guarda capturas)
import { chromium, Page } from "playwright-core";
import fs from "fs";
import path from "path";
import { createServer } from "vite";
import { startRpc } from "./rpc-server";

const CHROME = process.env.CHROME_PATH ?? "/opt/pw-browsers/chromium-1194/chrome-linux/chrome";
const SHOTS = process.env.SHOTS;
let shotN = 0;

async function main() {
  const rpc = await startRpc(8899);
  process.env.VITE_CLUSTER = "local";
  process.env.VITE_RPC_URL = rpc.url;
  const vite = await createServer({
    configFile: path.resolve("app/vite.config.ts"),
    server: { port: 5199, strictPort: true },
    logLevel: "error",
  });
  await vite.listen();
  const appUrl = "http://localhost:5199/";
  const browser = await chromium.launch({ executablePath: CHROME });
  const errors: string[] = [];

  const person = async (name: string) => {
    const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 } });
    const page = await ctx.newPage();
    page.on("pageerror", (e) => errors.push(`${name}: ${e.message}`));
    await page.goto(appUrl);
    await page.getByRole("button", { name: "Use a test wallet" }).click();
    await page.getByRole("button", { name: "Get 1 SOL" }).waitFor();
    const secret = JSON.parse((await page.evaluate(() => localStorage.getItem("owncurve.burner.v1")))!);
    const { Keypair } = await import("@solana/web3.js");
    const pk = Keypair.fromSecretKey(Uint8Array.from(secret)).publicKey;
    rpc.svm.airdrop(pk, 5_000_000_000n);
    const kp = Keypair.fromSecretKey(Uint8Array.from(secret));
    return { page, pk, kp };
  };
  const shot = async (page: Page, name: string) => {
    if (!SHOTS) return;
    fs.mkdirSync(SHOTS, { recursive: true });
    await page.screenshot({ path: `${SHOTS}/${String(++shotN).padStart(2, "0")}-${name}.png`, fullPage: true });
  };
  const ok = async (page: Page, text: RegExp | string) => {
    await page.getByRole("status").filter({ hasText: text }).waitFor({ timeout: 30_000 });
  };
  const step = (s: string) => console.log(`  ✔ ${s}`);

  try {
    const team = await person("equipo");
    const holder = await person("holder");
    await shot(team.page, "inicio-vacio");
    // El botón de airdrop de la wallet de prueba funciona contra la red
    await team.page.getByRole("button", { name: "Get 1 SOL" }).click();
    await team.page.getByText("1 devnet SOL added.").waitFor();
    step("wallets de prueba creadas y fondeadas");

    // 1. Lanzar
    await team.page.getByRole("link", { name: "Launch a raise" }).first().click();
    await team.page.getByLabel("Name").fill("Lighthouse Labs");
    await team.page.getByLabel("Symbol").fill("light");
    await shot(team.page, "formulario");
    await team.page.getByRole("button", { name: "Launch raise" }).click();
    await team.page.getByRole("heading", { name: /Lighthouse Labs/ }).waitFor({ timeout: 30_000 });
    const raiseUrl = team.page.url();
    await team.page.getByText("On the curve").first().waitFor();
    step(`raise lanzado: ${raiseUrl.split("/").pop()}`);
    await shot(team.page, "raise-en-curva");

    // 2. Holder compra, luego el equipo completa la curva
    await holder.page.goto(raiseUrl);
    await holder.page.getByLabel("SOL to spend").fill("0.2");
    await holder.page.getByRole("button", { name: "Buy LIGHT" }).click();
    await ok(holder.page, "Bought LIGHT.");
    step("holder compró 0.2 SOL");
    await team.page.getByLabel("SOL to spend").fill("0.5");
    await team.page.getByRole("button", { name: "Buy LIGHT" }).click();
    await ok(team.page, "Bought LIGHT.");
    await team.page.getByRole("button", { name: "Move the raise into the treasury" }).click();
    await ok(team.page, "The treasury is funded.");
    await team.page.getByText("Paying in tranches").first().waitFor();
    step("curva completa y tesorería financiada desde la interfaz");
    await shot(team.page, "tesoreria-financiada");

    // 3. Graduación a DAMM v2, venta de pánico y defensa del piso desde la interfaz
    await team.page.getByRole("button", { name: "Graduate the pool to Meteora DAMM v2" }).click();
    await ok(team.page, "The token now trades on DAMM v2.");
    await team.page.getByText("Price floor.").waitFor({ timeout: 30_000 });
    await panicSell(rpc.url, team.kp, raiseUrl.split("/").pop()!);
    await team.page.reload();
    await team.page.getByRole("button", { name: /Buy back below backing/ }).click();
    await ok(team.page, "Floor defended");
    await team.page.getByText(/tokens burned so far/).waitFor({ timeout: 30_000 });
    step("graduado a DAMM v2; tras una venta de pánico la tesorería recompró bajo el respaldo y quemó");
    await shot(team.page, "piso-defendido");

    // 4. El equipo pide el tramo 1 con evidencia; el holder la ve y objeta
    const evidenceUrl = "https://github.com/lighthouse/app/releases/tag/v0.1";
    await team.page.getByLabel("Link to the delivered work").fill(evidenceUrl);
    await team.page.getByLabel(/What you shipped/).fill("Beta live with 1,200 users");
    await team.page.getByRole("button", { name: /Request tranche 1/ }).click();
    await ok(team.page, "Tranche requested.");
    await holder.page.reload();
    await holder.page.getByRole("link", { name: evidenceUrl }).waitFor({ timeout: 30_000 });
    await holder.page.getByRole("button", { name: /Object with my/ }).click();
    await ok(holder.page, "Objection recorded.");
    step("tramo 1 pedido con evidencia (enlace + sha256 en cadena) y objetado por el holder");
    await shot(holder.page, "objecion");

    // 5. Pasa la ventana: se liquida
    rpc.svm && (await fetch(rpc.url, { method: "POST", body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "owncurve_warp", params: [61] }) }));
    await team.page.reload();
    await team.page.getByRole("button", { name: "Settle tranche 1" }).click();
    await ok(team.page, "Tranche settled.");
    await team.page.getByText("Holders redeeming").first().waitFor();
    step("ventana cerrada: el raise pasó a liquidación");
    await shot(team.page, "liquidacion");

    // 6. El holder desbloquea y redime
    await holder.page.reload();
    await holder.page.getByRole("button", { name: "Unlock my voted tokens" }).click();
    await ok(holder.page, "Your tokens are back");
    await holder.page.getByRole("button", { name: /Redeem my tokens for/ }).click();
    await ok(holder.page, "Redeemed.");
    step("el holder redimió sus tokens por SOL");
    await shot(holder.page, "redimido");

    // 6. La lista de inicio refleja el estado, aunque haya un raise de una versión vieja
    //    del programa (como el de la F1 en devnet, 8 bytes más corto).
    const { Keypair, PublicKey } = await import("@solana/web3.js");
    const idl = JSON.parse(fs.readFileSync("target/idl/owncurve.json", "utf8"));
    const disc = Buffer.from(idl.accounts.find((a: any) => a.name === "Raise").discriminator);
    const legacy = Keypair.generate().publicKey;
    rpc.svm.setAccount(legacy, { lamports: 10_000_000, data: Buffer.concat([disc, Buffer.alloc(227)]), owner: new PublicKey(idl.address), executable: false });
    await fetch(rpc.url, { method: "POST", body: JSON.stringify({ jsonrpc: "2.0", id: 2, method: "getAccountInfo", params: [legacy.toBase58()] }) });
    await team.page.goto(appUrl);
    await team.page.getByRole("cell", { name: /Lighthouse Labs/ }).waitFor();
    await team.page.getByText("Holders redeeming").first().waitFor();
    step("la lista de raises muestra el raise en liquidación");
    await shot(team.page, "inicio-con-raise");

    // Vista móvil
    await team.page.setViewportSize({ width: 390, height: 844 });
    await team.page.goto(raiseUrl);
    await team.page.getByRole("heading", { name: /Lighthouse Labs/ }).waitFor();
    await shot(team.page, "movil-raise");

    if (errors.length) throw new Error("Errores de JavaScript en la página:\n" + errors.join("\n"));
    console.log("\n  E2E OK: el ciclo completo funciona desde la interfaz.");
  } catch (e) {
    if (SHOTS) {
      for (const [i, pg] of browser.contexts().flatMap((c) => c.pages()).entries())
        await pg.screenshot({ path: `${SHOTS}/fallo-${i}.png`, fullPage: true }).catch(() => {});
    }
    throw e;
  } finally {
    await browser.close();
    await vite.close();
    rpc.server.close();
  }
}

/** Venta de pánico directa contra el RPC (no hay botón de vender en la app). */
async function panicSell(rpcUrl: string, team: import("@solana/web3.js").Keypair, config: string) {
  const { Connection, PublicKey, Transaction } = await import("@solana/web3.js");
  const { loadIdl } = await import("../../scripts/lib/net");
  const { OwnCurve, Raise } = await import("../../scripts/lib/owncurve");
  const conn = new Connection(rpcUrl, "confirmed");
  const net: any = {
    cluster: "local",
    conn,
    payer: team,
    explorer: (s: string) => s,
    advanceTime: async () => {},
    fund: async () => {},
    send: async (_l: string, ixs: any[], signers: any[]) => {
      const tx = new Transaction().add(...ixs);
      tx.feePayer = team.publicKey;
      tx.recentBlockhash = (await conn.getLatestBlockhash()).blockhash;
      tx.sign(team, ...signers.filter((k) => !k.publicKey.equals(team.publicKey)));
      return conn.sendRawTransaction(tx.serialize());
    },
  };
  const oc = new OwnCurve(net, loadIdl());
  const raise = await (oc.program.account as any).raise.fetch(
    PublicKey.findProgramAddressSync([Buffer.from("raise"), new PublicKey(config).toBuffer()], oc.programId)[0],
  );
  const r = new Raise(oc, new PublicKey(config), new PublicKey(raise.baseMint));
  const mine = await oc.tokenBalance(r.baseAta(team.publicKey));
  await oc.dammSell(r, mine.muln(6).divn(10));
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error(`\n  ✘ ${e.message ?? e}`);
    process.exit(1);
  });
OWNCURVE_EOF

mkdir -p 'app/src/lib'
cat > 'app/src/lib/data.ts' <<'OWNCURVE_EOF'
import { BN } from "@anchor-lang/core";
import bs58 from "bs58";
import { TOKEN_2022_PROGRAM_ID, getTokenMetadata } from "@solana/spl-token";
import { Connection, Keypair, LAMPORTS_PER_SOL, PublicKey } from "@solana/web3.js";
import { useCallback, useEffect, useRef, useState } from "react";
import idl from "../../../target/idl/owncurve.json";
import type { Net } from "../../../scripts/lib/net";
import { BASE_DECIMALS, OwnCurve, Raise, ps, stateName } from "../../../scripts/lib/owncurve";
import { CLUSTER } from "./browserNet";

export const IDL = idl as any;
export const PROGRAM_ID = new PublicKey(IDL.address);

/** Cliente de solo lectura (sin wallet): para listar y mostrar raises. */
export function readOnlyClient(conn: Connection) {
  const net: Net = {
    cluster: CLUSTER,
    conn,
    payer: { publicKey: PublicKey.default } as unknown as Keypair,
    send: async () => {
      throw new Error("Connect a wallet first");
    },
    explorer: (s) => s,
    advanceTime: async () => {},
    fund: async () => {},
  };
  return new OwnCurve(net, IDL);
}

export const lamportsToSol = (v: BN | number | bigint) => Number(v.toString()) / LAMPORTS_PER_SOL;
export const fmtSol = (v: BN | number | bigint, digits = 3) =>
  lamportsToSol(v).toLocaleString("en-US", { minimumFractionDigits: digits, maximumFractionDigits: digits });
export const fmtTokens = (v: BN) =>
  (Number(v.toString()) / 10 ** BASE_DECIMALS).toLocaleString("en-US", { maximumFractionDigits: 0 });

const DEFAULT = PublicKey.default;

async function tokenMeta(conn: Connection, mint: PublicKey) {
  try {
    const m = await getTokenMetadata(conn, mint, "confirmed", TOKEN_2022_PROGRAM_ID);
    if (m) return { name: m.name, symbol: m.symbol };
  } catch {
    /* sin metadata */
  }
  return { name: "Unnamed token", symbol: "?" };
}

export type RaiseRow = {
  config: string;
  name: string;
  symbol: string;
  state: string;
  treasurySol: number;
  progress: number | null; // 0..1 mientras está en la curva
  fundedSol: number;
};

export async function listRaises(oc: OwnCurve): Promise<RaiseRow[]> {
  // Todas las cuentas Raise (por discriminador); las de versiones anteriores del programa
  // (p. ej. las de F1/F3 en devnet) tienen otro formato: no decodifican y se ignoran.
  const disc = IDL.accounts.find((a: any) => a.name === "Raise").discriminator as number[];
  const raw = await oc.net.conn.getProgramAccounts(oc.programId, {
    filters: [{ memcmp: { offset: 0, bytes: bs58.encode(Uint8Array.from(disc)) } }],
  });
  const all: { publicKey: PublicKey; account: any }[] = [];
  for (const { pubkey, account } of raw) {
    try {
      const dec = oc.program.coder.accounts.decode("raise", account.data);
      if (typeof dec.proposalEvidenceUri !== "string" || dec.floorReserveBps > 5000) continue;
      all.push({ publicKey: pubkey, account: dec });
    } catch {
      /* formato antiguo */
    }
  }
  const rows = await Promise.all(
    all.map(async ({ account }) => {
      const config = new PublicKey(account.dbcConfig);
      const baseMint = new PublicKey(account.baseMint);
      const r = new Raise(oc, config, baseMint);
      const state = stateName(account.state);
      const bound = !baseMint.equals(DEFAULT);
      const meta = bound ? await tokenMeta(oc.net.conn, baseMint) : { name: "Not launched yet", symbol: "—" };
      let progress: number | null = null;
      if (state === "bonding") {
        try {
          const c = await oc.curve(r);
          progress = Math.min(1, lamportsToSol(c.reserve) / lamportsToSol(c.threshold));
        } catch {
          progress = 0;
        }
      }
      const treasury = bound ? await oc.tokenBalance(r.treasuryQuote) : new BN(0);
      return {
        config: config.toBase58(),
        ...meta,
        state,
        treasurySol: lamportsToSol(treasury),
        progress,
        fundedSol: lamportsToSol(account.fundedAmount),
      };
    }),
  );
  const order = ["bonding", "funded", "liquidating", "completed", "pending"];
  return rows.sort((a, b) => order.indexOf(a.state) - order.indexOf(b.state) || b.fundedSol - a.fundedSol);
}

export type Vote = { nonce: number; amount: BN };

export type RaiseDetail = {
  r: Raise;
  raise: any;
  state: string;
  name: string;
  symbol: string;
  team: PublicKey;
  curve: { reserve: BN; threshold: BN; complete: boolean; migrated: boolean } | null;
  cfg: any | null;
  treasuryQuote: BN;
  circulating: BN;
  navPerMillion: number; // SOL que recibe quien redime 1.000.000 tokens
  proposal: { milestone: number; endsAt: number; rejectWeight: BN; quorum: BN; evidenceUri: string; evidenceHash: string } | null;
  /** Lo que el equipo puede cobrar en tramos: financiado − reserva del piso. */
  payable: BN;
  floorReserve: BN;
  floorBudget: BN;
  /** Mercado DAMM v2 tras graduar: precio y respaldo en SOL por 1.000.000 tokens. */
  market: { pricePerMillion: number; backingPerMillion: number; suggest: BN } | null;
  user: { base: BN; sol: number; votes: Vote[] } | null;
  /** Segundos que el reloj de la cadena va por delante (+) o por detrás (−) del navegador. */
  clockSkew: number;
};

export async function loadRaise(oc: OwnCurve, config: PublicKey, user: PublicKey | null): Promise<RaiseDetail> {
  const raisePda = PublicKey.findProgramAddressSync([Buffer.from("raise"), config.toBuffer()], oc.programId)[0];
  const raise = await (oc.program.account as any).raise.fetch(raisePda);
  const baseMint = new PublicKey(raise.baseMint);
  const r = new Raise(oc, config, baseMint);
  const state = stateName(raise.state);
  const bound = !baseMint.equals(DEFAULT);
  const meta = bound ? await tokenMeta(oc.net.conn, baseMint) : { name: "Not launched yet", symbol: "—" };
  const cfg = await oc.dbc.state.getPoolConfig(config).catch(() => null);

  let curve: RaiseDetail["curve"] = null;
  let circulating = new BN(0);
  let treasuryQuote = new BN(0);
  if (bound) {
    const pool = await oc.dbc.state.getPool(r.pool).catch(() => null);
    if (pool && cfg) {
      const p = ps(pool);
      const threshold = new BN(cfg.migrationQuoteThreshold.toString());
      const reserve = new BN(p.quoteReserve.toString());
      curve = { reserve, threshold, complete: reserve.gte(threshold), migrated: Boolean(p.isMigrated) };
    }
    treasuryQuote = await oc.tokenBalance(r.treasuryQuote);
    circulating = (await oc.mintSupply(baseMint)).sub(await oc.tokenBalance(r.treasuryBase));
  }
  const navPerMillion = circulating.isZero()
    ? 0
    : (lamportsToSol(treasuryQuote) * 1_000_000 * 10 ** BASE_DECIMALS) / Number(circulating.toString());

  const active = raise.milestones.findIndex((m: any) => stateName(m.status) === "proposed");
  const proposal =
    state === "funded" && active >= 0
      ? {
          milestone: active,
          endsAt: Number(raise.proposalEndsAt.toString()),
          rejectWeight: new BN(raise.proposalRejectWeight.toString()),
          quorum: circulating.muln(raise.rejectQuorumBps).divn(10_000),
          evidenceUri: String(raise.proposalEvidenceUri ?? ""),
          evidenceHash: Buffer.from(raise.milestones[active].evidenceHash).toString("hex"),
        }
      : null;

  const funded = new BN(raise.fundedAmount.toString());
  const floorReserve = funded.muln(raise.floorReserveBps).divn(10_000);
  const payable = funded.sub(floorReserve);
  let floorBudget = floorReserve.add(new BN(raise.feesCollected.toString())).sub(new BN(raise.floorSpent.toString()));
  if (floorBudget.isNeg()) floorBudget = new BN(0);
  let market: RaiseDetail["market"] = null;
  if (curve?.migrated) {
    try {
      const st = await oc.dammState(r);
      if (st) {
        // lamports por unidad atómica → SOL por 1.000.000 tokens
        const k = (10 ** BASE_DECIMALS * 1_000_000) / LAMPORTS_PER_SOL;
        const backingUnit = circulating.isZero() ? 0 : Number(treasuryQuote.toString()) / Number(circulating.toString());
        const suggest = ["funded", "completed"].includes(state) ? await oc.suggestDefend(r) : new BN(0);
        market = { pricePerMillion: st.price * k, backingPerMillion: backingUnit * k, suggest };
      }
    } catch {
      /* pool aún no legible */
    }
  }

  let userInfo: RaiseDetail["user"] = null;
  if (user && bound) {
    const base = await oc.tokenBalance(r.baseAta(user));
    const sol = (await oc.net.conn.getBalance(user)) / LAMPORTS_PER_SOL;
    const nonces = Array.from({ length: Number(raise.proposalNonce) + 1 }, (_, i) => i);
    const infos = await oc.net.conn.getMultipleAccountsInfo(nonces.map((n) => r.voteRecord(user, n)));
    const votes: Vote[] = [];
    infos.forEach((info, i) => {
      if (!info) return;
      const v = oc.program.coder.accounts.decode("voteRecord", info.data);
      votes.push({ nonce: nonces[i], amount: new BN(v.amount.toString()) });
    });
    userInfo = { base, sol, votes };
  }

  let clockSkew = 0;
  try {
    const t = await oc.net.conn.getBlockTime(await oc.net.conn.getSlot());
    if (t) clockSkew = t - Math.floor(Date.now() / 1000);
  } catch {
    /* sin hora de la cadena: usamos la del navegador */
  }

  return {
    r,
    raise,
    state,
    clockSkew,
    ...meta,
    team: new PublicKey(raise.team),
    curve,
    cfg,
    treasuryQuote,
    circulating,
    navPerMillion,
    proposal,
    payable,
    floorReserve,
    floorBudget,
    market,
    user: userInfo,
  };
}

/** Lee `fn` al montar y cada `ms` milisegundos; `reload` fuerza una lectura inmediata. */
export function usePoll<T>(fn: () => Promise<T>, deps: unknown[], ms = 6000) {
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<string | null>(null);
  const fnRef = useRef(fn);
  fnRef.current = fn;
  const reload = useCallback(() => {
    fnRef
      .current()
      .then((d) => {
        setData(d);
        setError(null);
      })
      .catch((e) => setError(String(e?.message ?? e)));
  }, []);
  useEffect(() => {
    reload();
    const id = setInterval(reload, ms);
    return () => clearInterval(id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);
  return { data, error, reload };
}
OWNCURVE_EOF

mkdir -p 'app/src/components'
cat > 'app/src/components/VaultBar.tsx' <<'OWNCURVE_EOF'
// El elemento central de la interfaz: la tesorería dibujada como una bóveda dividida en
// tramos. Liberado = tinta llena; propuesto = latón con cuenta atrás; bloqueado = guilloché.
import { BN } from "@anchor-lang/core";
import { stateName } from "../../../scripts/lib/owncurve";
import { fmtSol } from "../lib/data";
import { useNow } from "../lib/useNow";

type Props = {
  state: string;
  raise: any;
  curve: { reserve: BN; threshold: BN } | null;
  treasuryPct: number;
  clockSkew?: number;
};

export function VaultBar({ state, raise, curve, treasuryPct, clockSkew = 0 }: Props) {
  const now = useNow(clockSkew);

  if (state === "pending" || state === "bonding") {
    const pct = curve ? Math.min(100, (Number(curve.reserve.toString()) / Number(curve.threshold.toString())) * 100) : 0;
    return (
      <figure className="vault" aria-label={`Bonding curve ${pct.toFixed(0)}% filled`}>
        <div className="vault-track curve">
          <div className="vault-fill" style={{ width: `${pct}%` }} />
        </div>
        <figcaption className="vault-caption">
          <span className="big">{curve ? fmtSol(curve.reserve) : "0.000"}</span>
          <span>
            of {curve ? fmtSol(curve.threshold) : "—"} SOL raised on the curve. At graduation {treasuryPct}% moves into
            the treasury.
          </span>
        </figcaption>
      </figure>
    );
  }

  // Los tramos reparten lo cobrable; la reserva del piso nunca va al equipo.
  const fundedAll = new BN(raise.fundedAmount.toString());
  const floorBps = Number(raise.floorReserveBps ?? 0);
  const floorAmount = fundedAll.muln(floorBps).divn(10_000);
  const funded = fundedAll.sub(floorAmount);
  const width = (bps: number) => (bps * (10_000 - floorBps)) / 10_000;
  const count = Number(raise.milestoneCount);
  const ms = raise.milestones.slice(0, count) as any[];
  let paidSoFar = new BN(0);
  const segments = ms.map((m, i) => {
    const isLast = i === count - 1;
    const amount = isLast
      ? funded.sub(ms.slice(0, i).reduce((a, x) => a.add(funded.muln(x.trancheBps).divn(10_000)), new BN(0)))
      : funded.muln(m.trancheBps).divn(10_000);
    const status = stateName(m.status);
    paidSoFar = status === "released" ? paidSoFar.add(amount) : paidSoFar;
    return { i, bps: m.trancheBps as number, amount, status };
  });
  const endsAt = Number(raise.proposalEndsAt.toString());
  const left = Math.max(0, endsAt - now);

  return (
    <figure className={`vault ${state}`} aria-label="Treasury tranches">
      <div className="vault-track">
        {segments.map((s) => (
          <div
            key={s.i}
            className={`seg ${state === "liquidating" && s.status !== "released" ? "returned" : s.status}`}
            style={{ flexGrow: width(s.bps) }}
          />
        ))}
        {floorBps > 0 && <div className="seg floor" style={{ flexGrow: floorBps }} />}
      </div>
      <ol className="seg-labels">
        {segments.map((s) => (
          <li key={s.i} style={{ flexGrow: width(s.bps) }}>
            <span className="amt">{fmtSol(s.amount)} SOL</span>
            <span className="what">
              Tranche {s.i + 1}, {s.bps / 100}%:{" "}
              {state === "liquidating" && s.status !== "released"
                ? "back to holders"
                : s.status === "released"
                  ? "paid to team"
                  : s.status === "proposed"
                    ? left > 0
                      ? `objections close in ${fmtLeft(left)}`
                      : "ready to settle"
                    : "locked"}
            </span>
          </li>
        ))}
        {floorBps > 0 && (
          <li className="floor" style={{ flexGrow: floorBps }}>
            <span className="amt">{fmtSol(floorAmount)} SOL</span>
            <span className="what">Price floor reserve: never paid to the team</span>
          </li>
        )}
      </ol>
    </figure>
  );
}

export function fmtLeft(secs: number) {
  const m = Math.floor(secs / 60);
  const s = Math.floor(secs % 60);
  return m > 0 ? `${m} min ${s.toString().padStart(2, "0")} s` : `${s} s`;
}
OWNCURVE_EOF

mkdir -p 'app/src/components'
cat > 'app/src/components/Guarantees.tsx' <<'OWNCURVE_EOF'
// Lo que bind_pool comprobó en cadena antes de que nadie comprara, releído en vivo de la
// config de Meteora DBC. Es la respuesta a "¿por qué no me pueden hacer un rug?".
import { PublicKey } from "@solana/web3.js";
import type { RaiseDetail } from "../lib/data";
import { explorerAddress } from "../lib/browserNet";

export function Guarantees({ d }: { d: RaiseDetail }) {
  const cfg = d.cfg;
  if (!cfg) return null;
  const treasury = d.r.treasury;
  const items: { ok: boolean; text: string }[] = [
    {
      ok: new PublicKey(cfg.feeClaimer).equals(treasury),
      text: "Only this program can move the raise: Meteora pays the migration fee to the treasury, not to a wallet.",
    },
    {
      ok: cfg.migrationFeePercentage >= d.raise.minTreasuryPct && cfg.creatorMigrationFeePercentage === 0,
      text: `${cfg.migrationFeePercentage}% of the raise goes to the treasury and 0% to the creator.`,
    },
    {
      ok: cfg.creatorLiquidityPercentage === 0 && cfg.creatorLiquidityVestingInfo.vestingPercentage === 0,
      text: "The team cannot pull liquidity after graduation: its LP share is permanently locked.",
    },
    {
      ok: cfg.tokenUpdateAuthority !== 3,
      text: "Nobody can mint more tokens.",
    },
    {
      ok: Number(d.raise.challengeWindow) >= 60 && d.raise.rejectQuorumBps <= 3000,
      text: `Every payment waits ${Number(d.raise.challengeWindow)} s for objections; ${
        d.raise.rejectQuorumBps / 100
      }% of the supply can stop it.`,
    },
    {
      ok: d.raise.floorReserveBps > 0,
      text: `${d.raise.floorReserveBps / 100}% of the treasury plus every fee it earns can only buy the token back below its backing and burn it.`,
    },
    {
      ok: true,
      text: "Every tranche request carries a public link to the delivered work and its SHA-256 on-chain.",
    },
  ];
  const link = explorerAddress(treasury);
  return (
    <section className="guarantees" aria-labelledby="g-title">
      <h2 id="g-title">Checked on-chain before the first buy</h2>
      <ul>
        {items.map((it) => (
          <li key={it.text} className={it.ok ? "ok" : "bad"}>
            <span className="mark" aria-hidden>
              {it.ok ? "✓" : "✕"}
            </span>
            {it.text}
          </li>
        ))}
      </ul>
      <p className="fine">
        Treasury account{" "}
        {link ? (
          <a className="addr" href={link} target="_blank" rel="noreferrer">
            {treasury.toBase58()}
          </a>
        ) : (
          <span className="addr">{treasury.toBase58()}</span>
        )}
      </p>
    </section>
  );
}
OWNCURVE_EOF

mkdir -p 'app/src/pages'
cat > 'app/src/pages/Create.tsx' <<'OWNCURVE_EOF'
import { Keypair } from "@solana/web3.js";
import { FormEvent, useState } from "react";
import { DEFAULT_PARAMS, OwnCurve } from "../../../scripts/lib/owncurve";
import { explainError, makeBrowserNet } from "../lib/browserNet";
import { IDL } from "../lib/data";
import { useAccount } from "../lib/wallet";

const METADATA_URI =
  "https://raw.githubusercontent.com/solana-developers/opos-asset/main/assets/DeveloperPortal/metadata.json";

export function Create() {
  const acc = useAccount();
  const [name, setName] = useState("");
  const [symbol, setSymbol] = useState("");
  const [target, setTarget] = useState("0.5");
  const [treasury, setTreasury] = useState("80");
  const [tranches, setTranches] = useState("30, 30, 40");
  const [windowSecs, setWindowSecs] = useState("60");
  const [quorum, setQuorum] = useState("10");
  const [floor, setFloor] = useState("20");
  const [step, setStep] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const trancheList = tranches
    .split(/[,\s]+/)
    .filter(Boolean)
    .map(Number);
  const trancheSum = trancheList.reduce((a, b) => a + b, 0);
  const formError =
    trancheList.some((t) => !Number.isFinite(t) || t <= 0) || trancheSum !== 100 || trancheList.length > 5
      ? "Tranches must be 1 to 5 positive numbers that add up to 100."
      : Number(treasury) < 50 || Number(treasury) > 99
        ? "Send between 50% and 99% of the raise to the treasury."
        : Number(windowSecs) < 60
          ? "Give holders at least 60 seconds to object."
          : Number(quorum) <= 0 || Number(quorum) > 30
            ? "The quorum must be between 1% and 30% of the supply."
            : !(Number(floor) >= 0 && Number(floor) <= 50)
              ? "Keep between 0% and 50% of the treasury as a price floor."
            : !(Number(target) > 0)
              ? "Set how much SOL the curve should raise."
              : null;

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    if (!acc.signer || formError) return;
    setError(null);
    try {
      const oc = new OwnCurve(makeBrowserNet(acc.conn, acc.signer), IDL);
      const configKp = Keypair.generate();
      const baseMintKp = Keypair.generate();
      const params = {
        ...DEFAULT_PARAMS,
        thresholdSol: Number(target),
        treasuryPct: Math.round(Number(treasury)),
        tranchesBps: trancheList.map((t) => Math.round(t * 100)),
        challengeSecs: Math.round(Number(windowSecs)),
        quorumBps: Math.round(Number(quorum) * 100),
        floorReserveBps: Math.round(Number(floor) * 100),
      };
      setStep("Creating the raise and its Meteora curve (1 of 2)…");
      await oc.createRaise(params, configKp);
      setStep("Opening the curve and checking it on-chain (2 of 2)…");
      await oc.launchPool(configKp.publicKey, baseMintKp, undefined, true, {
        name: name.trim(),
        symbol: symbol.trim().toUpperCase(),
        uri: METADATA_URI,
      });
      acc.refreshBalance();
      location.hash = `#/raise/${configKp.publicKey.toBase58()}`;
    } catch (err) {
      console.error(err);
      setError(explainError(err));
    } finally {
      setStep(null);
    }
  };

  return (
    <main className="page narrow">
      <h1>Launch a raise</h1>
      <p className="muted">
        Your token trades on a Meteora bonding curve. When the curve graduates, the share you choose goes to a treasury
        that pays you one tranche at a time.
      </p>
      <form className="form" onSubmit={submit}>
        <fieldset>
          <legend>Token</legend>
          <label>
            Name
            <input value={name} onChange={(e) => setName(e.target.value)} maxLength={32} required placeholder="Lighthouse Labs" />
          </label>
          <label>
            Symbol
            <input value={symbol} onChange={(e) => setSymbol(e.target.value)} maxLength={10} required placeholder="LIGHT" />
          </label>
        </fieldset>
        <fieldset>
          <legend>Raise</legend>
          <label>
            SOL the curve raises before graduating
            <input inputMode="decimal" value={target} onChange={(e) => setTarget(e.target.value)} />
          </label>
          <label>
            Share that goes to the treasury (%)
            <input inputMode="numeric" value={treasury} onChange={(e) => setTreasury(e.target.value)} />
          </label>
          <label>
            Tranches (% of the treasury, in order)
            <input value={tranches} onChange={(e) => setTranches(e.target.value)} />
            <small>Add up to 100. Now: {trancheSum}.</small>
          </label>
        </fieldset>
        <fieldset>
          <legend>Holder protection</legend>
          <label>
            Seconds holders have to object to each tranche
            <input inputMode="numeric" value={windowSecs} onChange={(e) => setWindowSecs(e.target.value)} />
          </label>
          <label>
            Supply that can stop a tranche (%)
            <input inputMode="decimal" value={quorum} onChange={(e) => setQuorum(e.target.value)} />
          </label>
          <label>
            Treasury kept as a price floor (%)
            <input inputMode="decimal" value={floor} onChange={(e) => setFloor(e.target.value)} />
            <small>Never paid to the team. If the token trades below its backing, it buys tokens back and burns them.</small>
          </label>
        </fieldset>
        {formError && <p className="error">{formError}</p>}
        {error && <p className="error">{error}</p>}
        {step && <p className="progress">{step}</p>}
        <button className="btn primary" disabled={!acc.signer || !!formError || !!step}>
          {acc.signer ? (step ? "Launching…" : "Launch raise") : "Connect a wallet to launch"}
        </button>
      </form>
    </main>
  );
}
OWNCURVE_EOF

mkdir -p 'app/src/pages'
cat > 'app/src/pages/RaisePage.tsx' <<'OWNCURVE_EOF'
import { BN } from "@anchor-lang/core";
import { LAMPORTS_PER_SOL, PublicKey } from "@solana/web3.js";
import { useMemo, useState } from "react";
import { OwnCurve, evidence, stateName } from "../../../scripts/lib/owncurve";
import { Guarantees } from "../components/Guarantees";
import { VaultBar, fmtLeft } from "../components/VaultBar";
import { makeBrowserNet } from "../lib/browserNet";
import { IDL, RaiseDetail, fmtSol, fmtTokens, loadRaise, readOnlyClient, usePoll } from "../lib/data";
import { useAction } from "../lib/useAction";
import { useNow } from "../lib/useNow";
import { short, useAccount } from "../lib/wallet";
import { STATE_LABEL } from "./Home";

export function RaisePage({ config }: { config: string }) {
  const acc = useAccount();
  const configKey = useMemo(() => {
    try {
      return new PublicKey(config);
    } catch {
      return null;
    }
  }, [config]);
  const reader = useMemo(() => readOnlyClient(acc.conn), [acc.conn]);
  const me = acc.signer?.publicKey ?? null;
  const { data: d, error, reload } = usePoll(
    () => (configKey ? loadRaise(reader, configKey, me) : Promise.reject(new Error("Invalid address"))),
    [reader, configKey?.toBase58(), me?.toBase58()],
    6000,
  );

  if (!configKey) return <main className="page"><p className="error">That is not a valid raise address.</p></main>;
  if (error && !d) return <main className="page"><p className="error">Could not load this raise: {error}</p></main>;
  if (!d) return <main className="page"><p className="muted">Reading the raise from the chain…</p></main>;

  const treasuryPct = d.cfg?.migrationFeePercentage ?? d.raise.minTreasuryPct;
  return (
    <main className="page raise">
      <div className="raise-head">
        <div>
          <p className="crumb">
            <a href="#/">Raises</a>
          </p>
          <h1>
            {d.name} <span className="sym">{d.symbol}</span>
          </h1>
        </div>
        <span className={`stage big ${d.state}`}>{STATE_LABEL[d.state] ?? d.state}</span>
      </div>

      <VaultBar state={d.state} raise={d.raise} curve={d.curve} treasuryPct={treasuryPct} clockSkew={d.clockSkew} />

      {d.state === "bonding" || d.state === "pending" ? (
        <dl className="figures">
          <div>
            <dt>Graduates at</dt>
            <dd>{d.curve ? fmtSol(d.curve.threshold) : "—"} SOL</dd>
          </div>
          <div>
            <dt>Goes to the treasury</dt>
            <dd>{d.curve ? fmtSol(d.curve.threshold.muln(treasuryPct).divn(100)) : "—"} SOL</dd>
          </div>
          <div>
            <dt>Kept as a price floor</dt>
            <dd>{d.raise.floorReserveBps / 100}% of the treasury</dd>
          </div>
          <div>
            <dt>Paid to the team in</dt>
            <dd>
              {Number(d.raise.milestoneCount)} tranches of{" "}
              {(d.raise.milestones as any[])
                .slice(0, Number(d.raise.milestoneCount))
                .map((m) => `${m.trancheBps / 100}%`)
                .join(", ")}
            </dd>
          </div>
        </dl>
      ) : (
        <dl className="figures">
          <div>
            <dt>Treasury holds</dt>
            <dd>{fmtSol(d.treasuryQuote)} SOL</dd>
          </div>
          <div>
            <dt>Paid to the team</dt>
            <dd>
              {fmtSol(d.raise.releasedAmount)} of {fmtSol(d.payable)} SOL
            </dd>
          </div>
          <div>
            <dt>Fees earned by the treasury</dt>
            <dd>{fmtSol(d.raise.feesCollected, 4)} SOL</dd>
          </div>
          <div>
            <dt>Treasury backing per 1,000,000 tokens</dt>
            <dd>{d.navPerMillion.toFixed(4)} SOL</dd>
          </div>
        </dl>
      )}

      <div className="columns">
        <Actions d={d} reload={reload} />
        <Guarantees d={d} />
      </div>
    </main>
  );
}

function Actions({ d, reload }: { d: RaiseDetail; reload: () => void }) {
  const acc = useAccount();
  const now = useNow(d.clockSkew);
  const act = useAction(() => {
    reload();
    acc.refreshBalance();
  });
  const [buySol, setBuySol] = useState("0.1");
  const [evUri, setEvUri] = useState("");
  const [evNote, setEvNote] = useState("");
  const evOk = /^https?:\/\/\S+$/.test(evUri.trim()) && evUri.trim().length <= 160;
  const oc = useMemo(() => (acc.signer ? new OwnCurve(makeBrowserNet(acc.conn, acc.signer), IDL) : null), [acc.conn, acc.signer]);

  const me = acc.signer?.publicKey;
  const isTeam = !!me && me.equals(d.team);
  const r = oc ? new (d.r.constructor as any)(oc, d.r.config, d.r.baseMint) : d.r;
  const nonce = Number(d.raise.proposalNonce);
  const lockedVotes = d.user?.votes.filter((v) => v.nonce < nonce) ?? [];
  const activeVote = d.user?.votes.find((v) => v.nonce === nonce);
  const nextMilestone = (d.raise.milestones as any[]).findIndex((m) => stateName(m.status) === "locked");
  const nextAmount =
    nextMilestone < 0
      ? null
      : nextMilestone === Number(d.raise.milestoneCount) - 1
        ? d.payable.sub(new BN(d.raise.releasedAmount.toString()))
        : d.payable.muln(d.raise.milestones[nextMilestone].trancheBps).divn(10_000);
  const windowOpen = d.proposal ? now < d.proposal.endsAt : false;
  const myBase = d.user?.base ?? new BN(0);
  const redeemPreview = d.circulating.isZero() ? 0 : (Number(myBase.toString()) / Number(d.circulating.toString())) * Number(d.treasuryQuote.toString());

  const buttons: JSX.Element[] = [];
  const btn = (key: string, label: string, done: string, fn: () => Promise<string | void>, primary = false) =>
    buttons.push(
      <button key={key} className={`btn ${primary ? "primary" : ""}`} disabled={!!act.busy} onClick={() => act.run(label, done, fn)}>
        {act.busy === label ? "Waiting for the network…" : label}
      </button>,
    );

  if (oc) {
    if (d.state === "bonding" && d.curve && !d.curve.complete) {
      buttons.push(
        <div key="buy" className="buy">
          <label>
            SOL to spend
            <input inputMode="decimal" value={buySol} onChange={(e) => setBuySol(e.target.value)} />
          </label>
          <button
            className="btn primary"
            disabled={!!act.busy || !(Number(buySol) > 0)}
            onClick={() =>
              act.run("Buy on the curve", `Bought ${d.symbol}.`, () =>
                oc.buy(r, new BN(Math.round(Number(buySol) * LAMPORTS_PER_SOL))),
              )
            }
          >
            {act.busy === "Buy on the curve" ? "Waiting for the network…" : `Buy ${d.symbol}`}
          </button>
        </div>,
      );
    }
    if (d.state === "bonding" && d.curve?.complete)
      btn("harvest", "Move the raise into the treasury", "The treasury is funded.", () => oc.harvest(r), true);

    if (d.state === "funded") {
      if (!d.proposal && isTeam && nextMilestone >= 0 && nextAmount) {
        const label = `Request tranche ${nextMilestone + 1} (${fmtSol(nextAmount)} SOL)`;
        buttons.push(
          <div key="propose" className="request">
            <label>
              Link to the delivered work
              <input
                type="url"
                placeholder="https://github.com/you/app/releases/tag/v1.0"
                value={evUri}
                onChange={(e) => setEvUri(e.target.value)}
              />
            </label>
            <label>
              What you shipped (its SHA-256 is stored on-chain)
              <input placeholder="Beta live: 1,200 users, audit report v1" value={evNote} onChange={(e) => setEvNote(e.target.value)} />
            </label>
            <button
              className="btn primary"
              disabled={!!act.busy || !evOk}
              onClick={() =>
                act.run(label, "Tranche requested. Holders can object until the countdown ends.", async () =>
                  oc.propose(r, undefined, await evidence(evUri.trim(), evNote)),
                )
              }
            >
              {act.busy === label ? "Waiting for the network…" : label}
            </button>
          </div>,
        );
      }
      if (d.proposal && windowOpen && myBase.gtn(0))
        btn(
          "reject",
          `Object with my ${fmtTokens(myBase)} tokens`,
          "Objection recorded. Your tokens unlock after the tranche is settled.",
          () => oc.reject(r, oc.net.payer, myBase),
        );
      if (d.proposal && !windowOpen)
        btn("finalize", `Settle tranche ${d.proposal.milestone + 1}`, "Tranche settled.", () => oc.finalize(r), true);
    }
    if (lockedVotes.length > 0)
      btn("withdraw", "Unlock my voted tokens", "Your tokens are back in your wallet.", async () => {
        let sig: string | undefined;
        for (const v of lockedVotes) sig = await oc.withdrawVote(r, oc.net.payer, v.nonce);
        return sig;
      });
    if (d.state === "liquidating" && myBase.gtn(0))
      btn(
        "redeem",
        `Redeem my tokens for ${(redeemPreview / LAMPORTS_PER_SOL).toFixed(4)} SOL`,
        "Redeemed. The SOL is in your wallet as wrapped SOL.",
        () => oc.redeem(r, oc.net.payer, myBase),
        true,
      );
    if (d.market && d.market.suggest.gtn(0))
      btn(
        "defend",
        `Buy back below backing with ${fmtSol(d.market.suggest, 4)} SOL and burn`,
        "Floor defended: the treasury bought tokens under their backing and burned them.",
        () => oc.defendFloor(r, d.market!.suggest),
        true,
      );
    if (["funded", "completed", "liquidating"].includes(d.state)) {
      if (d.curve && !d.curve.migrated)
        btn("migrate", "Graduate the pool to Meteora DAMM v2", "The token now trades on DAMM v2.", async () => (await oc.migrate(r)).sig);
      btn("fees", "Collect curve trading fees", "Fees moved into the treasury.", () => oc.collectTradingFees(r));
    }
  }

  return (
    <section className="actions" aria-labelledby="a-title">
      <h2 id="a-title">What you can do</h2>
      {d.proposal && (
        <div className="proposal">
          <p>
            <strong>Tranche {d.proposal.milestone + 1}</strong> is waiting.{" "}
            {windowOpen ? `Objections close in ${fmtLeft(d.proposal.endsAt - now)}.` : "The objection window has closed."}
          </p>
          {d.proposal.evidenceUri && (
            <p className="evidence">
              Evidence:{" "}
              <a href={d.proposal.evidenceUri} target="_blank" rel="noreferrer">
                {d.proposal.evidenceUri}
              </a>
              <br />
              <code title="SHA-256 committed on-chain with the request">sha256 {d.proposal.evidenceHash.slice(0, 16)}…</code>
            </p>
          )}
          <div className="quorum" aria-label="Objections against quorum">
            <span style={{ width: `${Math.min(100, quorumPct(d.proposal.rejectWeight, d.proposal.quorum))}%` }} />
          </div>
          <p className="fine">
            {fmtTokens(d.proposal.rejectWeight)} tokens object;{" "}
            {d.proposal.rejectWeight.gte(d.proposal.quorum)
              ? "that is enough to stop the payment and open redemptions."
              : `${fmtTokens(d.proposal.quorum)} would stop the payment and open redemptions.`}
          </p>
        </div>
      )}
      {d.market && <FloorPanel d={d} />}
      {!acc.signer && <p className="muted">Connect a wallet or use a test wallet to buy, object or redeem.</p>}
      {acc.signer && (
        <p className="fine">
          You hold {fmtTokens(myBase)} {d.symbol}
          {activeVote ? ` in your wallet and ${fmtTokens(activeVote.amount)} locked in an objection` : ""}
          {lockedVotes.length ? ` and ${fmtTokens(lockedVotes.reduce((a, v) => a.add(v.amount), new BN(0)))} ready to unlock` : ""}.{" "}
          {isTeam ? "You created this raise." : `Team: ${short(d.team)}.`}
        </p>
      )}
      <div className="buttons">{buttons}</div>
      {acc.signer && buttons.length === 0 && <p className="muted">Nothing to do right now for this wallet.</p>}
      {act.error && <p className="error" role="alert">{act.error}</p>}
      {act.done && (
        <p className="ok" role="status">
          {act.done.text}{" "}
          {act.done.link && (
            <a href={act.done.link} target="_blank" rel="noreferrer">
              View transaction
            </a>
          )}
        </p>
      )}
    </section>
  );
}

function FloorPanel({ d }: { d: RaiseDetail }) {
  const m = d.market!;
  const below = m.pricePerMillion < m.backingPerMillion;
  // escala: 0 … 2× el respaldo (el respaldo queda en el centro)
  const scale = Math.max(m.backingPerMillion * 2, m.pricePerMillion * 1.1, 1e-12);
  const pos = (v: number) => `${Math.min(100, (v / scale) * 100)}%`;
  const fmt = (v: number) => (v >= 0.01 ? v.toFixed(4) : v.toPrecision(3));
  return (
    <div className="floor-panel" aria-label="Market price against treasury backing">
      <p>
        <strong>Price floor.</strong> On Meteora DAMM v2, 1,000,000 {d.symbol} trade at <strong>{fmt(m.pricePerMillion)} SOL</strong>;
        the treasury backs them with <strong>{fmt(m.backingPerMillion)} SOL</strong>.
      </p>
      <div className="gauge">
        <span className="backing" style={{ left: pos(m.backingPerMillion) }} title="Treasury backing" />
        <span className={`price ${below ? "below" : ""}`} style={{ left: pos(m.pricePerMillion) }} title="Market price" />
      </div>
      <p className="fine">
        {below
          ? "The token trades below what the treasury holds for it. Anyone can make the treasury buy it back and burn it, which lifts the backing of every remaining token."
          : "The price is above the backing. If it ever drops below, anyone can trigger a buyback that burns the tokens."}{" "}
        Floor budget left: {fmtSol(d.floorBudget, 4)} SOL
        {Number(d.raise.tokensBurned) > 0 ? ` · ${fmtTokens(new BN(d.raise.tokensBurned.toString()))} tokens burned so far` : ""}.
      </p>
    </div>
  );
}

function quorumPct(weight: BN, quorum: BN) {
  return quorum.isZero() ? 0 : (Number(weight.toString()) / Number(quorum.toString())) * 100;
}
OWNCURVE_EOF

mkdir -p 'app/src'
cat > 'app/src/styles.css' <<'OWNCURVE_EOF'
/* OwnCurve · "papel de seguridad": papel verdoso, tinta profunda, guilloché en lo bloqueado. */
:root {
  --paper: #edf1ea;
  --paper-2: #e3e9df;
  --ink: #16302e;
  --ink-soft: #4e6662;
  --line: #c6d1c8;
  --vault: #2e6b57;
  --brass: #b07d2a;
  --intaglio: #a23b3b;
  --white: #f8faf6;

  --display: "Bricolage Grotesque Variable", "Bricolage Grotesque", system-ui, sans-serif;
  --text: "Public Sans", system-ui, sans-serif;

  --s1: 4px;
  --s2: 8px;
  --s3: 16px;
  --s4: 24px;
  --s5: 40px;
  --s6: 64px;
  color-scheme: light;
}

* {
  box-sizing: border-box;
}
html {
  background: var(--paper);
}
body {
  margin: 0;
  color: var(--ink);
  background: var(--paper);
  font: 400 16px/1.55 var(--text);
  font-variant-numeric: tabular-nums;
  -webkit-font-smoothing: antialiased;
}
a {
  color: var(--ink);
  text-decoration-thickness: 1px;
  text-underline-offset: 3px;
}
a:hover {
  color: var(--vault);
}
:focus-visible {
  outline: 2px solid var(--brass);
  outline-offset: 2px;
}
h1,
h2 {
  font-family: var(--display);
  font-weight: 700;
  letter-spacing: -0.02em;
  margin: 0;
}
h1 {
  font-size: clamp(2.2rem, 5vw, 3.6rem);
  line-height: 1.02;
  font-variation-settings: "wdth" 85;
}
h2 {
  font-size: 1.35rem;
  line-height: 1.2;
}
code,
.addr {
  font: inherit;
  word-break: break-all;
}
.muted {
  color: var(--ink-soft);
}
.fine {
  color: var(--ink-soft);
  font-size: 0.875rem;
}

/* ------------------------------------------------------------------ cabecera */
.masthead {
  border-bottom: 1px solid var(--line);
  background: var(--paper);
  position: sticky;
  top: 0;
  z-index: 5;
}
.masthead-row {
  max-width: 1120px;
  margin: 0 auto;
  padding: var(--s3) var(--s3);
  display: flex;
  align-items: center;
  gap: var(--s4);
  flex-wrap: wrap;
}
.wordmark {
  font-family: var(--display);
  font-weight: 800;
  font-size: 1.5rem;
  letter-spacing: -0.03em;
  text-decoration: none;
}
.wordmark span {
  font-weight: 400;
}
.nav {
  display: flex;
  gap: var(--s3);
}
.nav a {
  text-decoration: none;
  color: var(--ink-soft);
}
.nav a:hover {
  color: var(--ink);
}
.account {
  margin-left: auto;
  display: flex;
  align-items: center;
  gap: var(--s2);
  flex-wrap: wrap;
}
.network {
  font-size: 0.8rem;
  color: var(--ink-soft);
  border: 1px solid var(--line);
  border-radius: 999px;
  padding: 2px 10px;
}
.who {
  display: inline-flex;
  flex-direction: column;
  line-height: 1.15;
  font-size: 0.85rem;
  text-align: right;
}
.who span {
  color: var(--ink-soft);
}
.flash {
  max-width: 1120px;
  margin: 0 auto;
  padding: 0 var(--s3) var(--s2);
  font-size: 0.875rem;
  color: var(--ink-soft);
}

/* ------------------------------------------------------------------ botones */
.btn {
  font: 600 0.95rem/1 var(--text);
  color: var(--ink);
  background: var(--white);
  border: 1.5px solid var(--ink);
  border-radius: 6px;
  padding: 10px 16px;
  cursor: pointer;
  text-decoration: none;
  display: inline-block;
}
.btn:hover:not(:disabled) {
  background: var(--paper-2);
}
.btn.primary {
  background: var(--ink);
  color: var(--paper);
}
.btn.primary:hover:not(:disabled) {
  background: var(--vault);
  border-color: var(--vault);
  color: var(--white);
}
.btn.quiet {
  border-color: var(--line);
  font-weight: 400;
}
.btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

/* ------------------------------------------------------------------ páginas */
.page {
  max-width: 1120px;
  margin: 0 auto;
  padding: var(--s5) var(--s3) var(--s6);
}
.page.narrow {
  max-width: 680px;
}
.lede {
  max-width: 760px;
  padding: var(--s4) 0 var(--s6);
}
.lede p {
  font-size: 1.15rem;
  max-width: 62ch;
  margin: var(--s4) 0 var(--s4);
}

/* Registro de raises: filas, no tarjetas */
.ledger h2 {
  margin-bottom: var(--s3);
}
table {
  width: 100%;
  border-collapse: collapse;
}
th {
  text-align: left;
  font-weight: 600;
  font-size: 0.85rem;
  color: var(--ink-soft);
  border-bottom: 1.5px solid var(--ink);
  padding: var(--s2) var(--s2);
}
td {
  border-bottom: 1px solid var(--line);
  padding: var(--s3) var(--s2);
  vertical-align: middle;
}
tbody tr {
  cursor: pointer;
}
tbody tr:hover td {
  background: var(--paper-2);
}
td a {
  text-decoration: none;
}
.num {
  text-align: right;
}
.stage {
  font-size: 0.85rem;
  padding: 2px 10px;
  border-radius: 999px;
  border: 1px solid currentColor;
  white-space: nowrap;
}
.stage.bonding,
.stage.pending {
  color: var(--ink-soft);
}
.stage.funded {
  color: var(--brass);
}
.stage.completed {
  color: var(--vault);
}
.stage.liquidating {
  color: var(--intaglio);
}
.stage.big {
  font-size: 0.95rem;
  padding: 6px 14px;
}
.mini-track {
  display: inline-block;
  vertical-align: middle;
  margin-left: var(--s2);
  width: 80px;
  height: 6px;
  border-radius: 3px;
  background: var(--line);
  overflow: hidden;
}
.mini-track span {
  display: block;
  height: 100%;
  background: var(--ink);
}

/* ------------------------------------------------------------------ raise */
.raise-head {
  display: flex;
  justify-content: space-between;
  align-items: flex-end;
  gap: var(--s3);
  flex-wrap: wrap;
  margin-bottom: var(--s5);
}
.crumb {
  margin: 0 0 var(--s2);
  font-size: 0.9rem;
}
.sym {
  font-weight: 400;
  color: var(--ink-soft);
  font-size: 0.5em;
  letter-spacing: 0;
}

/* La bóveda */
.vault {
  margin: 0 0 var(--s5);
}
.vault-track {
  display: flex;
  gap: 3px;
  height: 56px;
  border: 1.5px solid var(--ink);
  border-radius: 8px;
  padding: 3px;
  background: var(--white);
}
.vault-track.curve {
  display: block;
  position: relative;
  /* lo que falta por recaudar lleva la misma trama que lo bloqueado */
  background:
    repeating-linear-gradient(60deg, transparent 0 5px, rgba(22, 48, 46, 0.16) 5px 6px),
    repeating-linear-gradient(-60deg, transparent 0 5px, rgba(22, 48, 46, 0.16) 5px 6px), var(--paper);
}
.vault-fill {
  height: 100%;
  border-radius: 5px;
  background: var(--ink);
  transition: width 600ms ease;
}
.seg {
  flex-basis: 0;
  border-radius: 5px;
}
.seg.released {
  background: var(--vault);
}
.seg.proposed {
  background: var(--brass);
}
/* guilloché: dos tramas finas cruzadas, como en el papel de seguridad */
.seg.locked {
  background:
    repeating-linear-gradient(60deg, transparent 0 5px, rgba(22, 48, 46, 0.22) 5px 6px),
    repeating-linear-gradient(-60deg, transparent 0 5px, rgba(22, 48, 46, 0.22) 5px 6px), var(--paper);
}
.seg.returned {
  background:
    repeating-linear-gradient(90deg, transparent 0 4px, rgba(162, 59, 59, 0.35) 4px 5px), #f3e6e4;
}
/* reserva del piso: verde bóveda en trama horizontal, se queda con los holders */
.seg.floor {
  background:
    repeating-linear-gradient(0deg, transparent 0 5px, rgba(46, 107, 87, 0.35) 5px 6px), #e3eee7;
  border: 1.5px solid var(--vault);
}
.seg-labels li.floor {
  border-left-color: var(--vault);
}
.vault-caption {
  display: flex;
  align-items: baseline;
  gap: var(--s3);
  flex-wrap: wrap;
  margin-top: var(--s3);
  color: var(--ink-soft);
}
.vault-caption .big {
  font-family: var(--display);
  font-size: 2.2rem;
  font-weight: 700;
  color: var(--ink);
}
.seg-labels {
  list-style: none;
  display: flex;
  gap: 3px;
  margin: var(--s2) 0 0;
  padding: 0 3px;
}
.seg-labels li {
  flex-basis: 0;
  min-width: 0;
  display: flex;
  flex-direction: column;
  border-left: 1.5px solid var(--ink);
  padding-left: var(--s2);
}
.seg-labels .amt {
  font-family: var(--display);
  font-weight: 700;
  font-size: 1.25rem;
}
.seg-labels .what {
  font-size: 0.85rem;
  color: var(--ink-soft);
}

.figures {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
  gap: var(--s4);
  margin: 0 0 var(--s5);
  padding: var(--s4) 0;
  border-top: 1px solid var(--line);
  border-bottom: 1px solid var(--line);
}
.figures dt {
  font-size: 0.85rem;
  color: var(--ink-soft);
}
.figures dd {
  margin: var(--s1) 0 0;
  font-size: 1.15rem;
  font-weight: 600;
}

.columns {
  display: grid;
  grid-template-columns: 1.1fr 1fr;
  gap: var(--s5);
  align-items: start;
}
.actions h2,
.guarantees h2 {
  margin-bottom: var(--s3);
}
.buttons {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  gap: var(--s2);
  margin: var(--s3) 0;
}
.buy {
  display: flex;
  align-items: flex-end;
  gap: var(--s2);
  flex-wrap: wrap;
}
.buy label {
  display: flex;
  flex-direction: column;
  font-size: 0.85rem;
  color: var(--ink-soft);
}
.buy input {
  width: 120px;
}
.proposal {
  border: 1.5px solid var(--brass);
  border-radius: 8px;
  padding: var(--s3);
  margin-bottom: var(--s3);
  background: #f6efe1;
}
.proposal p {
  margin: 0 0 var(--s2);
}
.quorum {
  height: 8px;
  border-radius: 4px;
  background: var(--white);
  border: 1px solid var(--line);
  overflow: hidden;
}
.quorum span {
  display: block;
  height: 100%;
  background: var(--intaglio);
}

.evidence {
  font-size: 0.875rem;
  overflow-wrap: anywhere;
}
.evidence code {
  font-size: 0.8rem;
  color: var(--ink-soft);
}
.request {
  display: flex;
  flex-direction: column;
  gap: var(--s2);
  width: 100%;
  border: 1.5px dashed var(--line);
  border-radius: 8px;
  padding: var(--s3);
}
.request label {
  display: flex;
  flex-direction: column;
  font-size: 0.85rem;
  color: var(--ink-soft);
}
.request input {
  width: 100%;
}
.floor-panel {
  border: 1.5px solid var(--vault);
  border-radius: 8px;
  padding: var(--s3);
  margin-bottom: var(--s3);
  background: #e9f1ec;
}
.floor-panel p {
  margin: 0 0 var(--s2);
}
.gauge {
  position: relative;
  height: 10px;
  border-radius: 5px;
  background: var(--white);
  border: 1px solid var(--line);
  margin: var(--s2) 0 var(--s3);
}
.gauge .backing {
  position: absolute;
  top: -5px;
  bottom: -5px;
  width: 2px;
  background: var(--vault);
}
.gauge .price {
  position: absolute;
  top: 50%;
  width: 14px;
  height: 14px;
  margin: -7px 0 0 -7px;
  border-radius: 50%;
  background: var(--ink);
  border: 2px solid var(--white);
}
.gauge .price.below {
  background: var(--intaglio);
}
.guarantees ul {
  list-style: none;
  margin: 0;
  padding: 0;
}
.guarantees li {
  display: grid;
  grid-template-columns: 28px 1fr;
  gap: var(--s2);
  padding: var(--s2) 0;
  border-bottom: 1px solid var(--line);
}
.guarantees .mark {
  width: 22px;
  height: 22px;
  border-radius: 50%;
  display: grid;
  place-items: center;
  font-size: 0.8rem;
  border: 1.5px solid var(--vault);
  color: var(--vault);
}
.guarantees li.bad .mark {
  border-color: var(--intaglio);
  color: var(--intaglio);
}

/* ------------------------------------------------------------------ formulario */
.form {
  margin-top: var(--s4);
  display: flex;
  flex-direction: column;
  gap: var(--s4);
}
fieldset {
  border: 0;
  border-top: 1.5px solid var(--ink);
  margin: 0;
  padding: var(--s3) 0 0;
  display: grid;
  gap: var(--s3);
}
legend {
  font-family: var(--display);
  font-weight: 700;
  font-size: 1.15rem;
  padding: 0 var(--s2) 0 0;
}
label {
  display: flex;
  flex-direction: column;
  gap: var(--s1);
  font-size: 0.95rem;
}
small {
  color: var(--ink-soft);
}
input {
  font: 400 1rem var(--text);
  color: var(--ink);
  background: var(--white);
  border: 1.5px solid var(--line);
  border-radius: 6px;
  padding: 10px 12px;
}
input:focus {
  border-color: var(--ink);
}

.error {
  color: var(--intaglio);
}
.ok {
  color: var(--vault);
}
.progress {
  color: var(--brass);
}

.foot {
  max-width: 1120px;
  margin: 0 auto;
  padding: var(--s4) var(--s3) var(--s5);
  border-top: 1px solid var(--line);
  color: var(--ink-soft);
  font-size: 0.875rem;
}

@media (max-width: 820px) {
  .figures {
    grid-template-columns: repeat(2, 1fr);
  }
  .network {
    display: none;
  }
  .masthead-row {
    gap: var(--s2) var(--s3);
  }
  .account .btn {
    padding: 8px 12px;
  }
  .columns {
    grid-template-columns: 1fr;
  }
  .account {
    margin-left: 0;
    width: 100%;
  }
  .seg-labels .amt {
    font-size: 1rem;
  }
}
@media (prefers-reduced-motion: reduce) {
  .vault-fill {
    transition: none;
  }
}
OWNCURVE_EOF

ok "programs/owncurve (12 instrucciones), scripts/cli.ts, skills/owncurve/SKILL.md, app/, tests/"

# =============================================================================
step "3/7 Dependencias y compilación"
# =============================================================================
run "npm ci" npm ci --no-audit --no-fund
run "anchor keys sync" anchor keys sync
run "anchor build (opt-level s: binario más pequeño)" anchor build --skip-lint --tools-version v1.52 --arch v0
PROGRAM_ID=$(solana address -k target/deploy/owncurve-keypair.json)
ok "owncurve.so: $(( $(stat -c %s target/deploy/owncurve.so) / 1024 )) KB · $(jq '.instructions | length' target/idl/owncurve.json) instrucciones"

# =============================================================================
step "4/7 Regresión en local antes de gastar SOL"
# =============================================================================
[ -f local/dynamic_bonding_curve.so ] && [ -f local/damm_v2.so ] || fail "Faltan local/*.so (los prepara el script de F2)"
echo "+ CLUSTER=local npx tsx --test tests/owncurve.test.ts" >> "$LOG"
if CLUSTER=local npx tsx --test tests/owncurve.test.ts > logs/tests.tap 2>&1; then
  ok "$(grep -c '^ok ' logs/tests.tap) tests de integración del programa (piso, evidencia, seguridad…)"
else
  cat logs/tests.tap >> "$LOG"; grep '^not ok' logs/tests.tap || true; fail "Algún test falló"
fi
cat logs/tests.tap >> "$LOG"
run "Test del CLI de la Agent Skill (proceso a proceso, por JSON-RPC)" npx tsx --test tests/cli.test.ts
run "Demo completa en local (ensayo general)" env CLUSTER=local npx tsx scripts/demo.ts
CHROME=$(command -v chromium || command -v chromium-browser || command -v google-chrome || true)
if [ -n "$CHROME" ]; then
  echo "+ CHROME_PATH=$CHROME npx tsx tests/e2e/ui.e2e.ts" >> "$LOG"
  if CHROME_PATH="$CHROME" timeout 420 npx tsx tests/e2e/ui.e2e.ts >> "$LOG" 2>&1; then
    ok "E2E en navegador: lanzar → graduar → defender el piso → tramo con evidencia → objeción → redención"
  else
    warn "El E2E en navegador falló en esta máquina (detalle en el log); sigo, no afecta a devnet"
  fi
else
  warn "Sin Chromium: se salta el E2E en navegador"
fi

# =============================================================================
step "5/7 Actualizar el programa en devnet"
# =============================================================================
run "solana config → RPC devnet" solana config set --url "$RPC"
WALLET=$(solana address)
SO=target/deploy/owncurve.so
SO_BYTES=$(stat -c %s "$SO")
SO_HASH=$(sha256sum "$SO" | awk '{print $1}')
HASH_FILE=.owncurve/deployed-devnet.sha256
mkdir -p .owncurve
rent_of() { solana rent "$1" --lamports 2>/dev/null | awk '/Rent-exempt minimum/{print $3}'; }
RENT_NEW=$(rent_of "$((SO_BYTES + 45))"); [ -n "$RENT_NEW" ] || RENT_NEW=$(( (SO_BYTES + 45 + 128) * 6960 ))
DEMO_COST=1300000000   # dos raises (0,5 + 0,3 SOL) + rentas + comisiones, con margen
BAL=$(solana balance --lamports | awk '{print $1}')

SHOW=$(solana program show "$PROGRAM_ID" 2>/dev/null || true)
if [ -n "$SHOW" ] && [ -f "$HASH_FILE" ] && [ "$(cat "$HASH_FILE")" = "$SO_HASH" ]; then
  ok "El programa en devnet ya es esta versión"
else
  OLD_LEN=$(echo "$SHOW" | grep -oE "Data Length: [0-9]+" | grep -oE "[0-9]+" || echo 0)
  RENT_OLD=0
  if [ "${OLD_LEN:-0}" -gt 0 ]; then RENT_OLD=$(rent_of "$((OLD_LEN + 45))"); [ -n "$RENT_OLD" ] || RENT_OLD=0; fi
  EXTEND=$(( RENT_NEW > RENT_OLD ? RENT_NEW - RENT_OLD : 0 ))
  NEED=$(( RENT_NEW + EXTEND + 60000000 ))   # el buffer se devuelve al terminar
  if [ "$BAL" -lt "$NEED" ]; then
    echo -e "${Y}  Saldo $(sol "$BAL") SOL; para subir el programa hacen falta ~$(sol "$NEED") SOL en ese momento (se devuelven ~$(sol "$RENT_NEW") al terminar).${N}"
    echo -e "${Y}  Pide SOL en https://faucet.solana.com → ${B}$WALLET${Y} y vuelve a ejecutar.${N}"
    exit 2
  fi
  if [ "$EXTEND" -gt 0 ]; then MORE="ampliar cuesta $(sol "$EXTEND") SOL"; else MORE="no hace falta ampliar"; fi
  ok "Saldo $(sol "$BAL") SOL · subiendo $((SO_BYTES / 1024)) KB (antes $((OLD_LEN / 1024)) KB: $MORE)"
  echo "  … 1–3 minutos"
  if solana program deploy "$SO" --program-id target/deploy/owncurve-keypair.json \
       --url "$RPC" --use-rpc --with-compute-unit-price 50000 --max-sign-attempts 30 >> "$LOG" 2>&1; then
    echo "$SO_HASH" > "$HASH_FILE"
    ok "Programa actualizado: https://explorer.solana.com/address/$PROGRAM_ID?cluster=devnet"
  else
    warn "El deploy falló. Recuperando el SOL del buffer…"
    solana program close --buffers --url "$RPC" >> "$LOG" 2>&1 && ok "Buffers cerrados, SOL devuelto" || warn "No se pudo cerrar el buffer (ver log)"
    fail "Deploy fallido; vuelve a ejecutar el script"
  fi
fi

BAL=$(solana balance --lamports | awk '{print $1}')
DEMO_V=$(jq -r '.version // 0' .owncurve/demo-devnet.json 2>/dev/null || echo 0)
if [ "$BAL" -lt "$DEMO_COST" ] && [ "$DEMO_V" != "2" ]; then
  echo -e "${Y}  Saldo $(sol "$BAL") SOL; la demo necesita ~$(sol "$DEMO_COST") SOL. Pide SOL en https://faucet.solana.com → $WALLET${N}"
  exit 2
fi

# =============================================================================
step "6/7 Demo nueva en devnet (~8 min: venta de pánico, defensa del piso, 3 tramos con evidencia, rechazo)"
# =============================================================================
echo "+ RPC_URL=… npx tsx scripts/demo.ts" >> "$LOG"
set +e
RPC_URL="$RPC" npx tsx scripts/demo.ts 2>&1 | grep -v "bigint: Failed to load bindings" | tee -a "$LOG"
D_EXIT=${PIPESTATUS[0]}
set -e
[ "$D_EXIT" = 0 ] || fail "La demo se detuvo (mensaje arriba). Vuelve a ejecutar: retoma desde el último paso"

# =============================================================================
step "7/7 Interfaz y git"
# =============================================================================
# Solo en tu máquina (app/.env.local está en .gitignore): la app usa tu RPC de devnet.
printf 'VITE_CLUSTER=devnet\nVITE_RPC_URL=%s\n' "$RPC" > app/.env.local
run "vite build" npx vite build --config app/vite.config.ts
CFG_A=$(jq -r '.raiseA.config' .owncurve/demo-result-devnet.json)
echo "+ CLI: show raise A" >> "$LOG"
RPC_URL="$RPC" npx tsx scripts/cli.ts show "$CFG_A" > .owncurve/cli-show-A.json 2>>"$LOG" && ok "CLI (Agent Skill) lee el raise A de devnet: estado $(jq -r .state .owncurve/cli-show-A.json), $(jq -r .floor.tokensBurned .owncurve/cli-show-A.json | cut -d. -f1) tokens quemados" || warn "El CLI no pudo leer el raise A (ver log)"

git add -A >> "$LOG" 2>&1
git diff --cached --quiet || git commit -qm "F4B: piso de precio (defend_floor), hitos con evidencia, Agent Skill + CLI, workflow de GitHub Pages" >> "$LOG" 2>&1
ok "Cambios guardados en git"

RES=.owncurve/demo-result-devnet.json
echo -e "\n${G}================ F4B COMPLETA ================${N}"
echo -e "  Program ID : ${B}$PROGRAM_ID${N}"
echo -e "  Raise A    : $(jq -r '.raiseA.state' $RES) · liberado $(jq -r '.raiseA.releasedSol' $RES)/$(jq -r '.raiseA.payableSol' $RES) SOL con evidencia · piso: $(jq -r '.raiseA.floorSpentSol' $RES) SOL recomprados y quemados · tesorería $(jq -r '.raiseA.treasuryNowSol' $RES) SOL"
echo -e "  Raise B    : $(jq -r '.raiseB.state' $RES) · financiado $(jq -r '.raiseB.fundedSol' $RES) SOL · el holder redimió por SOL"
echo -e "  Enlaces    : ~/owncurve/docs/DEMO-devnet.md"
echo -e "  Saldo      : $(solana balance)"
echo -e "\n  App: ${B}http://localhost:5173/#/raise/$CFG_A${N}  (raise A: panel del piso y tramos con evidencia)"
echo -e "  Pásame este resumen (o el error). Ctrl+C para parar la app."
if [ "${NO_SERVE:-0}" = "1" ]; then exit 0; fi
exec npx vite --config app/vite.config.ts --host 127.0.0.1 --port 5173
