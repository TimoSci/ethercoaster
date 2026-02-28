defmodule Ethercoaster.Validators.QueryResult do
  @moduledoc """
  Wraps the full result of a validator rewards query.
  """

  alias Ethercoaster.Validators.EpochReward

  defstruct [:pubkey, :validator_index, :epoch_rewards, :from_epoch, :to_epoch,
             :total_reward, :epoch_count]

  @type t :: %__MODULE__{
          pubkey: String.t(),
          validator_index: non_neg_integer(),
          epoch_rewards: [EpochReward.t()],
          from_epoch: non_neg_integer(),
          to_epoch: non_neg_integer(),
          total_reward: integer(),
          epoch_count: non_neg_integer()
        }
end
