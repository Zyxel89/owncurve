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

declare_id!("GBHTxatkmbAX5U7G65yXzDVAZjjjyW9btGZ1DNUHtcfh");

#[derive(AnchorSerialize, AnchorDeserialize, Clone)]
pub struct InitRaiseParams {
    pub min_treasury_pct: u8,
    pub tranche_bps: Vec<u16>,
    pub challenge_window: i64,
    pub reject_quorum_bps: u16,
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

        let raise = &mut ctx.accounts.raise;
        raise.team = ctx.accounts.team.key();
        raise.dbc_config = ctx.accounts.dbc_config.key();
        raise.state = RaiseState::Pending;
        raise.min_treasury_pct = params.min_treasury_pct;
        raise.milestone_count = n as u8;
        for (i, bps) in params.tranche_bps.iter().enumerate() {
            raise.milestones[i] = Milestone { tranche_bps: *bps, status: MilestoneStatus::Locked };
        }
        for i in n..MAX_MILESTONES {
            raise.milestones[i] = Milestone { tranche_bps: 0, status: MilestoneStatus::Released };
        }
        raise.challenge_window = params.challenge_window;
        raise.reject_quorum_bps = params.reject_quorum_bps;
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

    /// Team proposes releasing the next milestone tranche; opens the challenge window.
    pub fn propose_release(ctx: Context<TeamAction>) -> Result<()> {
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
        raise.proposal_milestone = next as u8;
        raise.proposal_reject_weight = 0;
        raise.proposal_ends_at = Clock::get()?
            .unix_timestamp
            .checked_add(raise.challenge_window)
            .ok_or(OwnCurveError::MathOverflow)?;
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
        let tranche = if is_last {
            raise.funded_amount.saturating_sub(raise.released_amount)
        } else {
            ((raise.funded_amount as u128) * (raise.milestones[idx].tranche_bps as u128)
                / (BPS as u128)) as u64
        };

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

    #[test]
    fn circulating_excludes_treasury_held() {
        assert_eq!(circulating_supply(1_000, 200), 800);
        assert_eq!(circulating_supply(100, 500), 0);
    }
}
