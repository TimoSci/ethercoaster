defmodule Ethercoaster.Validator.ProposalReward do
  @moduledoc """
  Block proposal reward for one slot.

  All reward fields are integers in Gwei.
  """

  defstruct [:epoch, :slot, :validator_index, :total]

  @type t :: %__MODULE__{
          epoch: non_neg_integer(),
          slot: non_neg_integer(),
          validator_index: non_neg_integer(),
          total: integer()
        }
end
