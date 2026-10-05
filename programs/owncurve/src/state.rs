use anchor_lang::prelude::*;

pub const RAISE_SEED: &[u8] = b"raise";
pub const TREASURY_SEED: &[u8] = b"treasury";
pub const ESCROW_SEED: &[u8] = b"escrow";
pub const VOTE_SEED: &[u8] = b"vote";
pub const GUARD_SEED: &[u8] = b"guard";

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

// ---------------------------------------------------------------------------
// Guard: holder protections that run on their own (kept in a separate account so the
// layout of `Raise` never changes for existing raises).
// ---------------------------------------------------------------------------

/// Minimum seconds the team can be silent before anyone can declare the raise abandoned.
pub const MIN_INACTIVITY: i64 = 60;
/// A takeover must pay holders at least TWAP × (1 + 10%) per token; Bedrock's default is +30%.
pub const MIN_BUYOUT_PREMIUM_BPS: u16 = 1_000;
pub const MAX_BUYOUT_PREMIUM_BPS: u16 = 10_000;
pub const MIN_TWAP_WINDOW: i64 = 60;
pub const OBSERVATIONS: usize = 16;
/// A TWAP needs at least this many price observations inside its window.
pub const MIN_TWAP_OBSERVATIONS: u8 = 3;

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Copy, Debug, Default, InitSpace)]
pub struct Observation {
    pub ts: i64,
    /// DAMM v2 price, quote atoms per base atom, Q64.64.
    pub price_q64: u128,
}

#[account]
#[derive(InitSpace)]
pub struct Guard {
    pub raise: Pubkey,
    /// Ghost-team protection: seconds without a tranche request after which anyone can
    /// return the treasury to holders.
    pub inactivity_secs: i64,
    /// When the inactivity clock started (set by `arm_guard` once the raise is funded).
    pub armed_at: i64,
    /// On-chain Bedrock clause: premium over the TWAP that any takeover must pay every holder.
    pub buyout_premium_bps: u16,
    pub twap_window_secs: i64,
    /// Minimum spacing between price observations (twap_window / 8).
    pub observe_interval_secs: i64,
    pub observations: [Observation; OBSERVATIONS],
    pub obs_head: u8,
    pub obs_count: u8,
    /// Set when a takeover happened.
    pub acquirer: Pubkey,
    pub buyout_price_q64: u128,
    pub abandoned: bool,
    pub bump: u8,
}
