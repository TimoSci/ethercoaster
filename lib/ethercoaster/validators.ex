defmodule Ethercoaster.Validators do
  @moduledoc """
  Context for querying validator attestation rewards from the Beacon Chain API.
  """

  alias Ethercoaster.BeaconChain.{Beacon, Node}
  alias Ethercoaster.Validators.{EpochReward, QueryResult}

  @max_epochs 100

  @doc """
  Queries attestation rewards for a validator over the last `last_n_slots` slots.

  Returns `{:ok, QueryResult.t()}` or `{:error, String.t()}`.
  """
  @spec query_rewards(String.t(), pos_integer()) :: {:ok, QueryResult.t()} | {:error, String.t()}
  def query_rewards(pubkey, last_n_slots) do
    with {:ok, validator_index} <- resolve_validator_index(pubkey),
         {:ok, head_slot} <- get_head_slot(),
         {:ok, {from_epoch, to_epoch}} <- compute_epoch_range(head_slot, last_n_slots) do
      epoch_rewards = fetch_epoch_rewards(from_epoch, to_epoch, validator_index)

      {:ok,
       %QueryResult{
         pubkey: pubkey,
         validator_index: validator_index,
         epoch_rewards: Enum.sort_by(epoch_rewards, & &1.epoch),
         from_epoch: from_epoch,
         to_epoch: to_epoch,
         total_reward: Enum.sum(Enum.map(epoch_rewards, & &1.total)),
         epoch_count: length(epoch_rewards)
       }}
    end
  end

  defp resolve_validator_index(pubkey) do
    case Beacon.get_validator("head", pubkey) do
      {:ok, %{"index" => index}} ->
        {:ok, parse_int(index)}

      {:error, %{message: message}} ->
        {:error, "Validator not found: #{message}"}

      {:error, _} ->
        {:error, "Validator not found"}
    end
  end

  defp get_head_slot do
    case Node.get_syncing() do
      {:ok, %{"head_slot" => head_slot}} ->
        {:ok, parse_int(head_slot)}

      {:error, %{message: message}} ->
        {:error, "Could not reach beacon node: #{message}"}

      {:error, _} ->
        {:error, "Could not reach beacon node"}
    end
  end

  defp compute_epoch_range(head_slot, last_n_slots) do
    to_epoch = div(head_slot, 32) - 1
    from_epoch = max(div(head_slot - last_n_slots, 32), 0)
    from_epoch = max(from_epoch, to_epoch - @max_epochs + 1)

    if to_epoch < 0 do
      {:error, "No completed epochs yet"}
    else
      from_epoch = max(from_epoch, 0)
      {:ok, {from_epoch, to_epoch}}
    end
  end

  defp fetch_epoch_rewards(from_epoch, to_epoch, validator_index) do
    index_str = Integer.to_string(validator_index)

    from_epoch..to_epoch
    |> Task.async_stream(
      fn epoch ->
        case Beacon.get_attestation_rewards(Integer.to_string(epoch), [index_str]) do
          {:ok, %{"total_rewards" => [reward | _]}} ->
            {:ok, EpochReward.from_api(reward, epoch)}

          {:error, _} ->
            :error
        end
      end,
      max_concurrency: 4,
      timeout: 30_000
    )
    |> Enum.flat_map(fn
      {:ok, {:ok, reward}} -> [reward]
      _ -> []
    end)
  end

  defp parse_int(val) when is_integer(val), do: val
  defp parse_int(val) when is_binary(val), do: String.to_integer(val)
end
