defmodule Ethercoaster.Validators do
  @moduledoc """
  Context for querying validator consensus-layer rewards from the Beacon Chain API.

  Supports three reward categories:
  - `:attestation` — head/target/source/inactivity per epoch
  - `:sync_committee` — sync committee rewards per epoch
  - `:block_proposal` — block proposal rewards per epoch
  """

  alias Ethercoaster.BeaconChain.{Beacon, Node, Validator}
  alias Ethercoaster.Validators.{EpochRow, ProposalReward, QueryResult, SyncReward}

  @max_epochs 100
  @slots_per_epoch 32

  defp max_concurrency do
    :ethercoaster
    |> Application.get_env(Ethercoaster.BeaconChain, [])
    |> Keyword.get(:max_concurrency, 16)
  end

  @type category :: :attestation | :sync_committee | :block_proposal

  @doc """
  Queries rewards for a validator over the last `last_n_slots` slots.

  `categories` is a list of reward types to fetch.
  Returns `{:ok, QueryResult.t()}` or `{:error, String.t()}`.
  """
  @spec query(String.t(), pos_integer(), [category()]) ::
          {:ok, QueryResult.t()} | {:error, String.t()}
  def query(pubkey, last_n_slots, categories) do
    with {:ok, validator_index} <- resolve_validator_index(pubkey),
         {:ok, head_slot} <- get_head_slot(),
         {:ok, {from_epoch, to_epoch}} <- compute_epoch_range(head_slot, last_n_slots) do
      index_str = Integer.to_string(validator_index)

      results =
        categories
        |> Enum.map(fn cat ->
          Task.async(fn -> {cat, fetch_category(cat, from_epoch, to_epoch, index_str)} end)
        end)
        |> Task.await_many(120_000)
        |> Map.new()

      epoch_rows = merge_epoch_rows(from_epoch, to_epoch, results, categories)

      total_reward =
        Enum.reduce(epoch_rows, 0, fn row, acc ->
          acc +
            (row.att_head || 0) + (row.att_target || 0) +
            (row.att_source || 0) + (row.att_inactivity || 0) +
            (row.sync_reward || 0) + (row.proposal_total || 0)
        end)

      {:ok,
       %QueryResult{
         pubkey: pubkey,
         validator_index: validator_index,
         epoch_rows: epoch_rows,
         from_epoch: from_epoch,
         to_epoch: to_epoch,
         total_reward: total_reward,
         epoch_count: length(epoch_rows),
         queried_categories: categories
       }}
    end
  end

  defp resolve_validator_index(pubkey) do
    case Beacon.get_validator("head", pubkey) do
      {:ok, %{"index" => index}} -> {:ok, parse_int(index)}
      {:error, %{message: message}} -> {:error, "Validator not found: #{message}"}
      {:error, _} -> {:error, "Validator not found"}
    end
  end

  defp get_head_slot do
    case Node.get_syncing() do
      {:ok, %{"head_slot" => head_slot}} -> {:ok, parse_int(head_slot)}
      {:error, %{message: message}} -> {:error, "Could not reach beacon node: #{message}"}
      {:error, _} -> {:error, "Could not reach beacon node"}
    end
  end

  defp compute_epoch_range(head_slot, last_n_slots) do
    to_epoch = div(head_slot, @slots_per_epoch) - 1
    from_epoch = max(div(head_slot - last_n_slots, @slots_per_epoch), 0)
    from_epoch = max(from_epoch, to_epoch - @max_epochs + 1)

    if to_epoch < 0 do
      {:error, "No completed epochs yet"}
    else
      {:ok, {max(from_epoch, 0), to_epoch}}
    end
  end

  defp fetch_category(:attestation, from_epoch, to_epoch, index_str),
    do: fetch_attestation_rewards(from_epoch, to_epoch, index_str)

  defp fetch_category(:sync_committee, from_epoch, to_epoch, index_str),
    do: fetch_sync_rewards(from_epoch, to_epoch, index_str)

  defp fetch_category(:block_proposal, from_epoch, to_epoch, index_str),
    do: fetch_proposal_rewards(from_epoch, to_epoch, index_str)

  # --- Attestation rewards ---

  defp fetch_attestation_rewards(from_epoch, to_epoch, index_str) do
    from_epoch..to_epoch
    |> Task.async_stream(
      fn epoch ->
        case Beacon.get_attestation_rewards(Integer.to_string(epoch), [index_str]) do
          {:ok, %{"total_rewards" => [reward | _]}} ->
            {:ok,
             %{
               epoch: epoch,
               head: parse_int(reward["head"]),
               target: parse_int(reward["target"]),
               source: parse_int(reward["source"]),
               inactivity: parse_int(reward["inactivity"])
             }}

          {:error, _} ->
            :error
        end
      end,
      max_concurrency: max_concurrency(),
      timeout: 30_000
    )
    |> Enum.flat_map(fn
      {:ok, {:ok, data}} -> [data]
      _ -> []
    end)
  end

  # --- Sync committee rewards ---

  defp fetch_sync_rewards(from_epoch, to_epoch, index_str) do
    periods = sync_periods(from_epoch, to_epoch)

    on_committee? =
      periods
      |> Task.async_stream(
        fn {period_start, _period_end} ->
          case Validator.get_sync_duties(Integer.to_string(period_start), [index_str]) do
            {:ok, validators} when is_list(validators) and validators != [] -> true
            _ -> false
          end
        end,
        max_concurrency: 2,
        timeout: 30_000
      )
      |> Enum.any?(fn
        {:ok, true} -> true
        _ -> false
      end)

    if on_committee? do
      from_epoch..to_epoch
      |> Task.async_stream(
        fn epoch ->
          first_slot = epoch * @slots_per_epoch
          last_slot = first_slot + @slots_per_epoch - 1

          slot_rewards =
            first_slot..last_slot
            |> Task.async_stream(
              fn slot ->
                case Beacon.get_sync_committee_rewards(Integer.to_string(slot), [index_str]) do
                  {:ok, [%{"reward" => reward} | _]} -> {:ok, parse_int(reward)}
                  _ -> {:ok, 0}
                end
              end,
              max_concurrency: max_concurrency(),
              timeout: 30_000
            )
            |> Enum.map(fn
              {:ok, {:ok, val}} -> val
              _ -> 0
            end)

          %SyncReward{
            epoch: epoch,
            validator_index: parse_int(index_str),
            reward: Enum.sum(slot_rewards)
          }
        end,
        max_concurrency: max_concurrency(),
        timeout: 60_000
      )
      |> Enum.flat_map(fn
        {:ok, reward} -> [reward]
        _ -> []
      end)
    else
      Enum.map(from_epoch..to_epoch, fn epoch ->
        %SyncReward{epoch: epoch, validator_index: parse_int(index_str), reward: 0}
      end)
    end
  end

  defp sync_periods(from_epoch, to_epoch) do
    from_period = div(from_epoch, 256)
    to_period = div(to_epoch, 256)

    Enum.map(from_period..to_period, fn period ->
      period_start = max(period * 256, from_epoch)
      period_end = min((period + 1) * 256 - 1, to_epoch)
      {period_start, period_end}
    end)
  end

  # --- Block proposal rewards ---

  defp fetch_proposal_rewards(from_epoch, to_epoch, index_str) do
    from_epoch..to_epoch
    |> Task.async_stream(
      fn epoch ->
        case Validator.get_proposer_duties(Integer.to_string(epoch)) do
          {:ok, duties} when is_list(duties) ->
            my_slots =
              duties
              |> Enum.filter(&(&1["validator_index"] == index_str))
              |> Enum.map(&parse_int(&1["slot"]))

            Enum.flat_map(my_slots, fn slot ->
              case Beacon.get_block_rewards(Integer.to_string(slot)) do
                {:ok, %{"total" => total}} ->
                  [
                    %ProposalReward{
                      epoch: epoch,
                      slot: slot,
                      validator_index: parse_int(index_str),
                      total: parse_int(total)
                    }
                  ]

                _ ->
                  []
              end
            end)

          _ ->
            []
        end
      end,
      max_concurrency: max_concurrency(),
      timeout: 30_000
    )
    |> Enum.flat_map(fn
      {:ok, proposals} -> proposals
      _ -> []
    end)
  end

  # --- Merge into EpochRows ---

  defp merge_epoch_rows(from_epoch, to_epoch, results, categories) do
    att_map =
      if :attestation in categories do
        Map.get(results, :attestation, []) |> Map.new(&{&1.epoch, &1})
      else
        %{}
      end

    sync_map =
      if :sync_committee in categories do
        Map.get(results, :sync_committee, []) |> Map.new(&{&1.epoch, &1})
      else
        %{}
      end

    proposal_map =
      if :block_proposal in categories do
        Map.get(results, :block_proposal, [])
        |> Enum.group_by(& &1.epoch)
        |> Map.new(fn {epoch, proposals} ->
          best = Enum.max_by(proposals, & &1.total, fn -> nil end)
          {epoch, best}
        end)
      else
        %{}
      end

    Enum.map(from_epoch..to_epoch, fn epoch ->
      att = Map.get(att_map, epoch)
      sync = Map.get(sync_map, epoch)
      proposal = Map.get(proposal_map, epoch)

      %EpochRow{
        epoch: epoch,
        att_head: att && att.head,
        att_target: att && att.target,
        att_source: att && att.source,
        att_inactivity: att && att.inactivity,
        sync_reward: if(:sync_committee in categories, do: (sync && sync.reward) || 0, else: nil),
        proposal_total: proposal && proposal.total,
        proposal_slot: proposal && proposal.slot
      }
    end)
  end

  defp parse_int(val) when is_integer(val), do: val
  defp parse_int(val) when is_binary(val), do: String.to_integer(val)
end
