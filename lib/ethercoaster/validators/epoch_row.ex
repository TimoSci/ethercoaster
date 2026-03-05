defmodule Ethercoaster.Validators.EpochRow do
  @moduledoc """
  Unified row for one epoch combining all reward categories.

  Fields for unqueried categories are nil.
  """

  defstruct [
    :epoch,
    # Attestation (nil if not queried)
    :att_head,
    :att_target,
    :att_source,
    :att_inactivity,
    # Sync committee (nil if not queried)
    :sync_reward,
    # Block proposal (nil if not queried)
    :proposal_total,
    :proposal_slot
  ]

  @type t :: %__MODULE__{
          epoch: non_neg_integer(),
          att_head: integer() | nil,
          att_target: integer() | nil,
          att_source: integer() | nil,
          att_inactivity: integer() | nil,
          sync_reward: integer() | nil,
          proposal_total: integer() | nil,
          proposal_slot: non_neg_integer() | nil
        }
end
