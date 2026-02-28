defmodule Ethercoaster.Validators.EpochReward do
  @moduledoc """
  One epoch's attestation reward breakdown for a validator.

  All reward fields are integers in Gwei. Negative values indicate penalties.
  """

  defstruct [:epoch, :validator_index, :head, :target, :source, :inactivity, :total]

  @type t :: %__MODULE__{
          epoch: non_neg_integer(),
          validator_index: non_neg_integer(),
          head: integer(),
          target: integer(),
          source: integer(),
          inactivity: integer(),
          total: integer()
        }

  @doc "Builds an `EpochReward` from the API reward map and epoch number."
  @spec from_api(map(), non_neg_integer()) :: t()
  def from_api(reward_map, epoch) do
    head = parse_int(reward_map["head"])
    target = parse_int(reward_map["target"])
    source = parse_int(reward_map["source"])
    inactivity = parse_int(reward_map["inactivity"])

    %__MODULE__{
      epoch: epoch,
      validator_index: parse_int(reward_map["validator_index"]),
      head: head,
      target: target,
      source: source,
      inactivity: inactivity,
      total: head + target + source + inactivity
    }
  end

  defp parse_int(val) when is_integer(val), do: val
  defp parse_int(val) when is_binary(val), do: String.to_integer(val)
end
