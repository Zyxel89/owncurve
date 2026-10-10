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

#[cfg(not(feature = "no-entrypoint"))]
solana_security_txt::security_txt! {
    name: "OwnCurve",
    project_url: "https://github.com/Zyxel89/owncurve",
    contacts: "link:https://github.com/Zyxel89/owncurve/security/advisories/new",
    policy: "https://github.com/Zyxel89/owncurve/blob/main/SECURITY.md",
    preferred_languages: "en,es",
    source_code: "https://github.com/Zyxel89/owncurve",
    auditors: "None (hackathon build, devnet only)"
}

declare_id!("GBHTxatkmbAX5U7G65yXzDVAZjjjyW9btGZ1DNUHtcfh");

#[derive(AnchorSerialize, AnchorDeserialize, Clone)]
pub struct InitRaiseParams {
    pub min_treasury_pct: u8,
    pub tranche_bps: Vec<u16>,
    pub challenge_window: i64,
    pub reject_quorum_bps: u16,
    pub floor_reserve_bps: u16,
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone)]
pub struct GuardParams {
    /// Seconds the team may go without requesting a tranche before holders get the treasury back.
    pub inactivity_secs: i64,
    /// Premium over the TWAP a takeover must pay every holder (bps; Bedrock uses 3000 = +30%).
    pub buyout_premium_bps: u16,
    pub twap_window_secs: i64,
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone)]
pub struct BudgetParams {
    /// Quote atoms the team may draw per period.
    pub monthly_amount: u64,
    pub period_secs: i64,
}

#[event]
pub struct BudgetDrawn {
    pub raise: Pubkey,
    pub amount: u64,
    pub drawn_total: u64,
    pub advanced_on_next_tranche: u64,
}

#[event]
pub struct TeamAbandoned {
    pub raise: Pubkey,
    pub silent_since: i64,
    pub declared_at: i64,
}

#[event]
pub struct PriceObserved {
    pub raise: Pubkey,
    pub ts: i64,
    pub price_q64: u128,
}

#[event]
pub struct BuyoutExecuted {
    pub raise: Pubkey,
    pub acquirer: Pubkey,
    pub twap_q64: u128,
    pub buyout_price_q64: u128,
    pub circulating: u64,
    pub deposit: u64,
    pub treasury_after: u64,
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

        // Budget advances already paid count against this tranche (the last one is net already).
        let mut pay = tranche;
        let budget_info = ctx.accounts.budget.to_account_info();
        let mut budget: Option<Budget> = None;
        if budget_info.owner == &crate::ID && !budget_info.data_is_empty() {
            let mut b = Budget::try_deserialize(&mut &budget_info.try_borrow_data()?[..])?;
            if !is_last {
                let used = b.advanced_unsettled.min(tranche);
                pay = tranche - used;
                b.advanced_unsettled -= used;
            } else {
                b.advanced_unsettled = 0;
            }
            budget = Some(b);
        }

        let config_key = raise.dbc_config;
        let seeds: &[&[u8]] = &[TREASURY_SEED, config_key.as_ref(), &[raise.treasury_bump]];
        if pay > 0 {
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
                pay,
                ctx.accounts.quote_mint.decimals,
            )?;
        }
        if let Some(b) = budget {
            let mut data = budget_info.try_borrow_mut_data()?;
            b.try_serialize(&mut &mut data[..])?;
        }

        let raise = &mut ctx.accounts.raise;
        raise.milestones[idx].status = MilestoneStatus::Released;
        raise.released_amount = raise
            .released_amount
            .checked_add(pay)
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

    // -----------------------------------------------------------------------
    // Guard: protections that run on their own
    // -----------------------------------------------------------------------

    /// Team opts the raise into the guard before it is funded (usually in the launch transaction).
    pub fn init_guard(ctx: Context<InitGuard>, params: GuardParams) -> Result<()> {
        let raise = &ctx.accounts.raise;
        require!(
            raise.state == RaiseState::Pending || raise.state == RaiseState::Bonding,
            OwnCurveError::InvalidState
        );
        require!(
            params.inactivity_secs >= MIN_INACTIVITY
                && (MIN_BUYOUT_PREMIUM_BPS..=MAX_BUYOUT_PREMIUM_BPS).contains(&params.buyout_premium_bps)
                && params.twap_window_secs >= MIN_TWAP_WINDOW,
            OwnCurveError::InvalidGuard
        );
        let guard = &mut ctx.accounts.guard;
        guard.raise = raise.key();
        guard.inactivity_secs = params.inactivity_secs;
        guard.buyout_premium_bps = params.buyout_premium_bps;
        guard.twap_window_secs = params.twap_window_secs;
        guard.observe_interval_secs = (params.twap_window_secs / 8).max(1);
        guard.bump = ctx.bumps.guard;
        Ok(())
    }

    /// Starts the inactivity clock once the treasury is funded. Permissionless, once.
    pub fn arm_guard(ctx: Context<GuardOnly>) -> Result<()> {
        require!(ctx.accounts.raise.state == RaiseState::Funded, OwnCurveError::InvalidState);
        let guard = &mut ctx.accounts.guard;
        if guard.armed_at == 0 {
            guard.armed_at = Clock::get()?.unix_timestamp.max(1); // 0 = no armado
        }
        Ok(())
    }

    /// Ghost-team protection: if the team has not requested a tranche for `inactivity_secs`,
    /// anyone can turn the treasury into a redemption pool for holders.
    pub fn declare_abandoned(ctx: Context<GuardOnly>) -> Result<()> {
        let now = Clock::get()?.unix_timestamp;
        let guard = &ctx.accounts.guard;
        let raise = &ctx.accounts.raise;
        require!(raise.state == RaiseState::Funded, OwnCurveError::InvalidState);
        require!(guard.armed_at > 0, OwnCurveError::GuardNotArmed);
        let pending = raise.milestones[..raise.milestone_count as usize]
            .iter()
            .any(|m| m.status == MilestoneStatus::Proposed);
        require!(!pending, OwnCurveError::TeamStillActive);
        let silent_since = guard.armed_at.max(raise.proposal_ends_at);
        require!(
            now >= silent_since.checked_add(guard.inactivity_secs).ok_or(OwnCurveError::MathOverflow)?,
            OwnCurveError::TeamStillActive
        );
        ctx.accounts.raise.state = RaiseState::Liquidating;
        ctx.accounts.guard.abandoned = true;
        emit!(TeamAbandoned { raise: ctx.accounts.raise.key(), silent_since, declared_at: now });
        Ok(())
    }

    /// Records the DAMM v2 price for the guard's on-chain TWAP. Permissionless crank.
    pub fn observe(ctx: Context<Observe>) -> Result<()> {
        let raise = &ctx.accounts.raise;
        require!(
            raise.state == RaiseState::Funded || raise.state == RaiseState::Completed,
            OwnCurveError::InvalidState
        );
        let price_q64 = damm_price_q64(&ctx.accounts.damm_pool, raise)?;
        let now = Clock::get()?.unix_timestamp;
        let guard = &mut ctx.accounts.guard;
        if guard.obs_count > 0 {
            let last = guard.observations[(guard.obs_head as usize + OBSERVATIONS - 1) % OBSERVATIONS];
            require!(now >= last.ts + guard.observe_interval_secs, OwnCurveError::ObservationTooSoon);
        }
        let head = guard.obs_head as usize;
        guard.observations[head] = Observation { ts: now, price_q64 };
        guard.obs_head = ((head + 1) % OBSERVATIONS) as u8;
        guard.obs_count = (guard.obs_count + 1).min(OBSERVATIONS as u8);
        emit!(PriceObserved { raise: raise.key(), ts: now, price_q64 });
        Ok(())
    }

    /// On-chain Bedrock clause. The only way to take over a raise is a tender offer to every
    /// holder: the acquirer tops the treasury up until each circulating token redeems for at
    /// least TWAP × (1 + premium). The raise then pays holders out pro rata and the acquirer
    /// becomes its `team`.
    pub fn tender_offer(ctx: Context<TenderOffer>, max_deposit: u64) -> Result<()> {
        let raise = &ctx.accounts.raise;
        require!(
            raise.state == RaiseState::Funded || raise.state == RaiseState::Completed,
            OwnCurveError::InvalidState
        );
        let now = Clock::get()?.unix_timestamp;
        let guard = &ctx.accounts.guard;
        let twap = twap_q64(guard, now)?;
        let buyout_price = twap
            .checked_mul((BPS + guard.buyout_premium_bps as u64) as u128)
            .ok_or(OwnCurveError::MathOverflow)?
            / (BPS as u128);
        let circulating = circulating_supply(ctx.accounts.base_mint.supply, ctx.accounts.treasury_base.amount);
        require!(circulating > 0, OwnCurveError::NothingToDefend);
        let required = mul_shr64(buyout_price, circulating).ok_or(OwnCurveError::MathOverflow)?;
        let deposit = u64::try_from(required.saturating_sub(ctx.accounts.treasury_quote.amount as u128))
            .map_err(|_| error!(OwnCurveError::MathOverflow))?;
        require!(deposit <= max_deposit, OwnCurveError::BuyoutAboveMax);

        if deposit > 0 {
            token_interface::transfer_checked(
                CpiContext::new(
                    ctx.accounts.quote_token_program.key(),
                    TransferChecked {
                        from: ctx.accounts.acquirer_quote.to_account_info(),
                        mint: ctx.accounts.quote_mint.to_account_info(),
                        to: ctx.accounts.treasury_quote.to_account_info(),
                        authority: ctx.accounts.acquirer.to_account_info(),
                    },
                ),
                deposit,
                ctx.accounts.quote_mint.decimals,
            )?;
        }
        ctx.accounts.treasury_quote.reload()?;

        let acquirer = ctx.accounts.acquirer.key();
        let raise = &mut ctx.accounts.raise;
        // An open tranche request dies with the takeover: its votes become withdrawable.
        let count = raise.milestone_count as usize;
        if let Some(m) = raise.milestones[..count].iter_mut().find(|m| m.status == MilestoneStatus::Proposed) {
            m.status = MilestoneStatus::Locked;
            raise.proposal_nonce += 1;
        }
        raise.state = RaiseState::Liquidating;
        raise.team = acquirer;
        let guard = &mut ctx.accounts.guard;
        guard.acquirer = acquirer;
        guard.buyout_price_q64 = buyout_price;
        emit!(BuyoutExecuted {
            raise: raise.key(),
            acquirer,
            twap_q64: twap,
            buyout_price_q64: buyout_price,
            circulating,
            deposit,
            treasury_after: ctx.accounts.treasury_quote.amount,
        });
        Ok(())
    }
    // -----------------------------------------------------------------------
    // Operating budget: bounded monthly allowance, advanced against the next tranche
    // -----------------------------------------------------------------------

    pub fn init_budget(ctx: Context<InitBudget>, params: BudgetParams) -> Result<()> {
        let raise = &ctx.accounts.raise;
        require!(
            raise.state == RaiseState::Pending || raise.state == RaiseState::Bonding,
            OwnCurveError::InvalidState
        );
        require!(params.monthly_amount > 0 && params.period_secs >= MIN_BUDGET_PERIOD, OwnCurveError::InvalidBudget);
        let b = &mut ctx.accounts.budget;
        b.raise = raise.key();
        b.monthly_amount = params.monthly_amount;
        b.period_secs = params.period_secs;
        b.bump = ctx.bumps.budget;
        Ok(())
    }

    /// Team draws what has accrued this period, capped by what is still un-advanced on its
    /// next tranche. Only while the raise is Funded.
    pub fn draw_budget(ctx: Context<DrawBudget>) -> Result<()> {
        let raise = &ctx.accounts.raise;
        require!(raise.state == RaiseState::Funded, OwnCurveError::InvalidState);
        let now = Clock::get()?.unix_timestamp;
        let count = raise.milestone_count as usize;
        let next = raise.milestones[..count]
            .iter()
            .position(|m| m.status != MilestoneStatus::Released)
            .ok_or(OwnCurveError::NothingToDraw)?;
        let next_amount = tranche_amount(raise, next);

        let b = &mut ctx.accounts.budget;
        if b.start_at == 0 {
            b.start_at = now.max(1);
        }
        let periods = ((now - b.start_at) / b.period_secs + 1) as u64;
        let accrued = b.monthly_amount.checked_mul(periods).ok_or(OwnCurveError::MathOverflow)?;
        let amount = accrued
            .saturating_sub(b.drawn_total)
            .min(next_amount.saturating_sub(b.advanced_unsettled))
            .min(ctx.accounts.treasury_quote.amount);
        require!(amount > 0, OwnCurveError::NothingToDraw);

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
            amount,
            ctx.accounts.quote_mint.decimals,
        )?;
        b.drawn_total += amount;
        b.advanced_unsettled += amount;
        let (drawn_total, advanced) = (b.drawn_total, b.advanced_unsettled);
        let raise = &mut ctx.accounts.raise;
        raise.released_amount = raise.released_amount.checked_add(amount).ok_or(OwnCurveError::MathOverflow)?;
        emit!(BudgetDrawn { raise: raise.key(), amount, drawn_total, advanced_on_next_tranche: advanced });
        Ok(())
    }
}

/// `a × b / 2^64` without overflowing u128 when `a` is a Q64.64 number.
fn mul_shr64(a: u128, b: u64) -> Option<u128> {
    let hi = (a >> 64).checked_mul(b as u128)?;
    let lo = ((a & u64::MAX as u128) * (b as u128)) >> 64;
    hi.checked_add(lo)
}

/// DAMM v2 `Pool` layout (Meteora damm-v2 IDL, program cpamdp…): discriminator, mints, sqrt_price.
const DAMM_POOL_DISC: [u8; 8] = [0xf1, 0x9a, 0x6d, 0x04, 0x11, 0xb1, 0x6d, 0xbc];
const DAMM_TOKEN_A_MINT: usize = 168;
const DAMM_TOKEN_B_MINT: usize = 200;
const DAMM_SQRT_PRICE: usize = 456;

/// Spot price of the raise's DAMM v2 pool (quote atoms per base atom, Q64.64), after checking
/// that the account really is that pool.
fn damm_price_q64(pool: &UncheckedAccount, raise: &Raise) -> Result<u128> {
    require_keys_eq!(*pool.owner, damm_v2::ID, OwnCurveError::InvalidDammPool);
    let data = pool.try_borrow_data()?;
    require!(data.len() >= DAMM_SQRT_PRICE + 16 && data[..8] == DAMM_POOL_DISC, OwnCurveError::InvalidDammPool);
    let mint_a = Pubkey::try_from(&data[DAMM_TOKEN_A_MINT..DAMM_TOKEN_A_MINT + 32]).unwrap();
    let mint_b = Pubkey::try_from(&data[DAMM_TOKEN_B_MINT..DAMM_TOKEN_B_MINT + 32]).unwrap();
    require!(mint_a == raise.base_mint && mint_b == raise.quote_mint, OwnCurveError::InvalidDammPool);
    let sqrt = u128::from_le_bytes(data[DAMM_SQRT_PRICE..DAMM_SQRT_PRICE + 16].try_into().unwrap());
    // price = sqrt² / 2^64 in Q64.64; split to stay inside u128
    let s = sqrt >> 32;
    s.checked_mul(s).ok_or(error!(OwnCurveError::MathOverflow))
}

/// Average of the observations inside the TWAP window (they are spaced at least
/// `observe_interval_secs` apart, so the mean is time-weighted up to that granularity).
fn twap_q64(guard: &Guard, now: i64) -> Result<u128> {
    let from = now - guard.twap_window_secs;
    let mut sum: u128 = 0;
    let mut n: u128 = 0;
    let mut oldest = i64::MAX;
    for o in guard.observations.iter().take(guard.obs_count as usize) {
        if o.ts >= from {
            sum = sum.checked_add(o.price_q64).ok_or(OwnCurveError::MathOverflow)?;
            n += 1;
            oldest = oldest.min(o.ts);
        }
    }
    require!(
        n >= MIN_TWAP_OBSERVATIONS as u128 && now - oldest >= guard.twap_window_secs / 2,
        OwnCurveError::TwapNotReady
    );
    Ok(sum / n)
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
    /// CHECK: the raise's Budget PDA; empty when the raise has no budget.
    #[account(mut, seeds = [BUDGET_SEED, raise.key().as_ref()], bump)]
    pub budget: UncheckedAccount<'info>,
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

#[derive(Accounts)]
pub struct InitGuard<'info> {
    #[account(mut, address = raise.team)]
    pub team: Signer<'info>,
    #[account(seeds = [RAISE_SEED, raise.dbc_config.as_ref()], bump = raise.bump)]
    pub raise: Box<Account<'info, Raise>>,
    #[account(init, payer = team, space = 8 + Guard::INIT_SPACE, seeds = [GUARD_SEED, raise.key().as_ref()], bump)]
    pub guard: Box<Account<'info, Guard>>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct GuardOnly<'info> {
    #[account(mut, seeds = [RAISE_SEED, raise.dbc_config.as_ref()], bump = raise.bump)]
    pub raise: Box<Account<'info, Raise>>,
    #[account(mut, seeds = [GUARD_SEED, raise.key().as_ref()], bump = guard.bump)]
    pub guard: Box<Account<'info, Guard>>,
}

#[derive(Accounts)]
pub struct Observe<'info> {
    #[account(seeds = [RAISE_SEED, raise.dbc_config.as_ref()], bump = raise.bump)]
    pub raise: Box<Account<'info, Raise>>,
    #[account(mut, seeds = [GUARD_SEED, raise.key().as_ref()], bump = guard.bump)]
    pub guard: Box<Account<'info, Guard>>,
    /// CHECK: owner, discriminator and mints checked in `damm_price_q64`
    pub damm_pool: UncheckedAccount<'info>,
}

#[derive(Accounts)]
pub struct TenderOffer<'info> {
    #[account(mut)]
    pub acquirer: Signer<'info>,
    #[account(mut, seeds = [RAISE_SEED, raise.dbc_config.as_ref()], bump = raise.bump)]
    pub raise: Box<Account<'info, Raise>>,
    #[account(mut, seeds = [GUARD_SEED, raise.key().as_ref()], bump = guard.bump)]
    pub guard: Box<Account<'info, Guard>>,
    /// CHECK: PDA (authority of the treasury token accounts)
    #[account(seeds = [TREASURY_SEED, raise.dbc_config.as_ref()], bump = raise.treasury_bump)]
    pub treasury: UncheckedAccount<'info>,
    #[account(mut, token::mint = quote_mint, token::authority = treasury, token::token_program = quote_token_program)]
    pub treasury_quote: Box<InterfaceAccount<'info, TokenAccount>>,
    #[account(token::mint = base_mint, token::authority = treasury)]
    pub treasury_base: Box<InterfaceAccount<'info, TokenAccount>>,
    #[account(mut, token::mint = quote_mint, token::authority = acquirer, token::token_program = quote_token_program)]
    pub acquirer_quote: Box<InterfaceAccount<'info, TokenAccount>>,
    #[account(address = raise.quote_mint)]
    pub quote_mint: Box<InterfaceAccount<'info, Mint>>,
    #[account(address = raise.base_mint)]
    pub base_mint: Box<InterfaceAccount<'info, Mint>>,
    pub quote_token_program: Interface<'info, TokenInterface>,
}

#[derive(Accounts)]
pub struct InitBudget<'info> {
    #[account(mut, address = raise.team)]
    pub team: Signer<'info>,
    #[account(seeds = [RAISE_SEED, raise.dbc_config.as_ref()], bump = raise.bump)]
    pub raise: Box<Account<'info, Raise>>,
    #[account(init, payer = team, space = 8 + Budget::INIT_SPACE, seeds = [BUDGET_SEED, raise.key().as_ref()], bump)]
    pub budget: Box<Account<'info, Budget>>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct DrawBudget<'info> {
    #[account(address = raise.team)]
    pub team: Signer<'info>,
    #[account(mut, seeds = [RAISE_SEED, raise.dbc_config.as_ref()], bump = raise.bump)]
    pub raise: Box<Account<'info, Raise>>,
    #[account(mut, seeds = [BUDGET_SEED, raise.key().as_ref()], bump = budget.bump)]
    pub budget: Box<Account<'info, Budget>>,
    /// CHECK: PDA signer
    #[account(seeds = [TREASURY_SEED, raise.dbc_config.as_ref()], bump = raise.treasury_bump)]
    pub treasury: UncheckedAccount<'info>,
    #[account(mut, token::mint = quote_mint, token::authority = treasury, token::token_program = quote_token_program)]
    pub treasury_quote: Box<InterfaceAccount<'info, TokenAccount>>,
    #[account(mut, token::mint = quote_mint, token::authority = raise.team, token::token_program = quote_token_program)]
    pub team_quote: Box<InterfaceAccount<'info, TokenAccount>>,
    #[account(address = raise.quote_mint)]
    pub quote_mint: Box<InterfaceAccount<'info, Mint>>,
    pub quote_token_program: Interface<'info, TokenInterface>,
}
