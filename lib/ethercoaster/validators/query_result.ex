defmodule Ethercoaster.Validators.QueryResult do
  @moduledoc """
  Wraps the full result of a validator rewards query.
  """

  alias Ethercoaster.Validators.EpochRow

  defstruct [
    :pubkey,
    :validator_index,
    :from_epoch,
    :to_epoch,
    :epoch_count,
    :total_reward,
    :queried_categories,
    epoch_rows: []
  ]

  @type t :: %__MODULE__{
          pubkey: String.t(),
          validator_index: non_neg_integer(),
          epoch_rows: [EpochRow.t()],
          from_epoch: non_neg_integer(),
          to_epoch: non_neg_integer(),
          total_reward: integer(),
          epoch_count: non_neg_integer(),
          queried_categories: [atom()]
        }
end
