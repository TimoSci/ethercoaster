# Balance-Changing Events (Consensus Layer)

  1. Sync Committee Rewards

  When a validator is randomly selected to participate in a sync committee (every ~27 hours, serving for ~256 epochs), they earn rewards for
  each slot they sign. This is a significant income source when selected.

  2. Block Proposal Rewards (Consensus portion)

  When a validator is selected to propose a block, they earn consensus-layer rewards for:
  - Attestation inclusion (packing attestations into the block)
  - Sync committee inclusion
  - Slashing inclusion (including slashing evidence)

  3. Slashing Penalties

  If a validator commits a slashable offense (double voting or surround voting):
  - Initial penalty: immediate slash of 1/32 of effective balance
  - Correlation penalty: additional penalty proportional to how many other validators were slashed in the same time window (up to full
  effective balance)
  - Ongoing penalties: attestation penalties during the ~36-day forced exit period

  4. Inactivity Leak Penalties

  During periods where the chain fails to finalize (>4 epochs), all validators that fail to attest suffer escalating quadratic inactivity
  penalties. (You track inactivity already, but this becomes much more severe during non-finality.)

#  Balance-Changing Events (Execution Layer)

  5. Block Proposal Tips (Priority Fees)

  When proposing a block, the validator (via their fee recipient address) collects priority fees / tips from transactions. These go to an
  execution-layer address, not the validator balance.

  6. MEV Rewards

  If the validator uses MEV-Boost, the block builder pays a bid to the proposer's fee recipient. This is typically the largest single income
  event for a validator.

  Lifecycle Transactions

  7. Deposit

  The initial 32 ETH deposit (or top-up deposits) that activates the validator.

  8. Voluntary Exit

  A validator-initiated exit from the active set. No penalty, but the validator enters the exit queue and stops earning rewards.

  9. Withdrawals

  - Partial withdrawals (skimming): automatic sweep of balance above 32 ETH to the withdrawal address (happens periodically as the beacon
  chain cycles through validators)
  - Full withdrawals: after a validator has exited and the withdrawable epoch is reached, the full balance is withdrawn

  10. Consolidation (post-Pectra / EIP-7251)

  With MaxEB raised to 2048 ETH, validators can consolidate multiple 32-ETH validators into a single one.

 # Summary Table

  ┌────────────────┬───────────────────────────────┬───────────┬────────────────────┐
  │    Category    │             Event             │   Where   │ Currently Tracked? │
  ├────────────────┼───────────────────────────────┼───────────┼────────────────────┤
  │ Attestation    │ Head/Target/Source rewards    │ Consensus │ Yes                │
  ├────────────────┼───────────────────────────────┼───────────┼────────────────────┤
  │ Attestation    │ Inactivity penalty            │ Consensus │ Yes                │
  ├────────────────┼───────────────────────────────┼───────────┼────────────────────┤
  │ Sync Committee │ Sync committee rewards        │ Consensus │ No                 │
  ├────────────────┼───────────────────────────────┼───────────┼────────────────────┤
  │ Block Proposal │ Consensus proposal reward     │ Consensus │ No                 │
  ├────────────────┼───────────────────────────────┼───────────┼────────────────────┤
  │ Block Proposal │ Priority fees (tips)          │ Execution │ No                 │
  ├────────────────┼───────────────────────────────┼───────────┼────────────────────┤
  │ Block Proposal │ MEV rewards                   │ Execution │ No                 │
  ├────────────────┼───────────────────────────────┼───────────┼────────────────────┤
  │ Slashing       │ Initial + correlation penalty │ Consensus │ No                 │
  ├────────────────┼───────────────────────────────┼───────────┼────────────────────┤
  │ Lifecycle      │ Deposit                       │ Consensus │ No                 │
  ├────────────────┼───────────────────────────────┼───────────┼────────────────────┤
  │ Lifecycle      │ Voluntary exit                │ Consensus │ No                 │
  ├────────────────┼───────────────────────────────┼───────────┼────────────────────┤
  │ Lifecycle      │ Partial withdrawal (skim)     │ Consensus │ No                 │
  ├────────────────┼───────────────────────────────┼───────────┼────────────────────┤
  │ Lifecycle      │ Full withdrawal               │ Consensus │ No                 │
  ├────────────────┼───────────────────────────────┼───────────┼────────────────────┤
  │ Lifecycle      │ Consolidation                 │ Consensus │ No                 │
  └────────────────┴───────────────────────────────┴───────────┴────────────────────┘

