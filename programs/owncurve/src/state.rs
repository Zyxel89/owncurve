use anchor_lang::prelude::*;

pub const RAISE_SEED: &[u8] = b"raise";
pub const TREASURY_SEED: &[u8] = b"treasury";
pub const ESCROW_SEED: &[u8] = b"escrow";
pub const VOTE_SEED: &[u8] = b"vote";

pub const MAX_MILESTONES: usize = 5;
pub const BPS: u64 = 10_000;

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
    /// Share of the funded treasury released at this milestone, in bps.
    pub tranche_bps: u16,
    pub status: MilestoneStatus,
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
