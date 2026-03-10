defmodule Ethercoaster.BeaconChain.Rewards do
  @moduledoc """
  Higher-level reward fetching functions that compose multiple beacon chain API calls.
  """

  alias Ethercoaster.BeaconChain.Beacon
  alias Ethercoaster.BeaconChain.Validator, as: ValidatorAPI

  @doc """
  Fetches consensus block proposal rewards for a single validator across a range of epochs.

  Two-pass approach:
  1. Fetch proposer duties for each epoch, filter to slots assigned to `validator_index`
  2. Fetch block rewards for those slots only

  Returns `{:ok, [%{epoch: int, slot: int, total: int}]}` where total is in Gwei.
  """
  def fetch_proposal_rewards(epochs, validator_index) do
    max_concurrency = get_max_concurrency()
    index_str = to_string(validator_index)

    # Pass 1: find slots where this validator is the proposer
    assigned_slots =
      epochs
      |> Task.async_stream(
        fn epoch ->
          case ValidatorAPI.get_proposer_duties(epoch) do
            {:ok, duties} when is_list(duties) ->
              duties
              |> Enum.filter(fn duty -> to_string(duty["validator_index"]) == index_str end)
              |> Enum.map(fn duty ->
                %{epoch: epoch, slot: parse_int(duty["slot"])}
              end)

            _ ->
              []
          end
        end,
        max_concurrency: max_concurrency,
        timeout: 30_000
      )
      |> Enum.flat_map(fn
        {:ok, slots} -> slots
        _ -> []
      end)

    if assigned_slots == [] do
      {:ok, []}
    else
      # Pass 2: fetch block rewards for assigned slots
      rewards =
        assigned_slots
        |> Task.async_stream(
          fn %{epoch: epoch, slot: slot} ->
            case Beacon.get_block_rewards(slot) do
              {:ok, %{"proposer_index" => _, "total" => total}} ->
                {:ok, %{epoch: epoch, slot: slot, total: parse_int(total)}}

              {:error, %{status: 404}} ->
                # Slot was missed (no block produced)
                :skip

              {:error, _} ->
                :error
            end
          end,
          max_concurrency: max_concurrency,
          timeout: 30_000
        )
        |> Enum.flat_map(fn
          {:ok, {:ok, reward}} -> [reward]
          _ -> []
        end)

      {:ok, rewards}
    end
  end

  defp get_max_concurrency do
    :ethercoaster
    |> Application.get_env(Ethercoaster.BeaconChain, [])
    |> Keyword.get(:max_concurrency, 16)
  end

  defp parse_int(val) when is_integer(val), do: val
  defp parse_int(val) when is_binary(val), do: String.to_integer(val)
end
