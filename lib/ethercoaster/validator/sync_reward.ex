defmodule Ethercoaster.Validator.SyncReward do
  @moduledoc """
  Aggregated sync committee reward for one epoch (sum of per-slot rewards).

  All reward fields are integers in Gwei.
  """

  defstruct [:epoch, :validator_index, :reward]

  @type t :: %__MODULE__{
          epoch: non_neg_integer(),
          validator_index: non_neg_integer(),
          reward: integer()
        }
end
