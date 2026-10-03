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
}
