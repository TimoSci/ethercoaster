defmodule Ethercoaster.BeaconChain.Rewards do
  @moduledoc """
  Higher-level reward fetching functions that compose multiple beacon chain API calls.
  """

  alias Ethercoaster.BeaconChain.{Beacon, Client}
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
    base_url = Client.get_base_url()

    # Pass 1: find slots where this validator is the proposer
    assigned_slots =
      epochs
      |> Task.async_stream(
        fn epoch ->
          Client.put_base_url(base_url)

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
            Client.put_base_url(base_url)

            case Beacon.get_block_rewards(slot) do
              {:ok, %{"proposer_index" => _, "total" => total}} ->
                {:ok, %{
                  epoch: epoch,
                  slot: slot,
                  total: parse_int(total),
                  execution_block_hash: fetch_execution_block_hash(slot)
                }}

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

  @doc """
  Fetches execution block hashes for a list of consensus proposals.
  Each proposal must have a `:slot` key. Returns the proposals with
  `:execution_block_hash` populated.
  """
  def fetch_execution_block_hashes(proposals) do
    max_concurrency = get_max_concurrency()
    base_url = Client.get_base_url()

    proposals
    |> Task.async_stream(
      fn %{slot: slot} = proposal ->
        Client.put_base_url(base_url)
        Map.put(proposal, :execution_block_hash, fetch_execution_block_hash(slot))
      end,
      max_concurrency: max_concurrency,
      timeout: 30_000
    )
    |> Enum.flat_map(fn
      {:ok, result} -> [result]
      _ -> []
    end)
  end

  defp fetch_execution_block_hash(slot) do
    case Beacon.get_block(slot) do
      {:ok, block_data} ->
        get_in(block_data, ["message", "body", "execution_payload", "block_hash"])

      _ ->
        nil
    end
  end

  @slots_per_epoch 32

  @doc """
  Fetches sync committee rewards for a single validator across a range of epochs.

  Two-pass approach:
  1. Check sync committee membership per 256-epoch period
  2. For periods where the validator is on committee, fetch per-slot rewards

  Returns `{:ok, [%SyncReward{}]}`.
  """
  def fetch_sync_rewards(epochs, validator_index) do
    epoch_list = Enum.to_list(epochs)

    if epoch_list == [] do
      {:ok, []}
    else
      max_concurrency = get_max_concurrency()
      index_str = to_string(validator_index)
      base_url = Client.get_base_url()

      from_epoch = Enum.min(epoch_list)
      to_epoch = Enum.max(epoch_list)
      periods = sync_periods(from_epoch, to_epoch)

      # Pass 1: check which periods have this validator on committee
      active_periods =
        periods
        |> Task.async_stream(
          fn {period_start, _period_end} = period ->
            Client.put_base_url(base_url)

            case ValidatorAPI.get_sync_duties(to_string(period_start), [index_str]) do
              {:ok, validators} when is_list(validators) and validators != [] -> {:active, period}
              _ -> :inactive
            end
          end,
          max_concurrency: 2,
          timeout: 30_000
        )
        |> Enum.flat_map(fn
          {:ok, {:active, period}} -> [period]
          _ -> []
        end)

      # Determine which epochs fall within active periods
      active_epoch_set =
        active_periods
        |> Enum.flat_map(fn {period_start, period_end} ->
          Enum.filter(epoch_list, &(&1 >= period_start and &1 <= period_end))
        end)
        |> MapSet.new()

      # Pass 2: fetch per-slot rewards for active epochs, zero for inactive
      rewards =
        epoch_list
        |> Task.async_stream(
          fn epoch ->
            if MapSet.member?(active_epoch_set, epoch) do
              Client.put_base_url(base_url)
              first_slot = epoch * @slots_per_epoch
              last_slot = first_slot + @slots_per_epoch - 1

              slot_rewards =
                first_slot..last_slot
                |> Task.async_stream(
                  fn slot ->
                    Client.put_base_url(base_url)

                    case Beacon.get_sync_committee_rewards(to_string(slot), [index_str]) do
                      {:ok, [%{"reward" => reward} | _]} -> {:ok, parse_int(reward)}
                      _ -> {:ok, 0}
                    end
                  end,
                  max_concurrency: max_concurrency,
                  timeout: 30_000
                )
                |> Enum.map(fn
                  {:ok, {:ok, val}} -> val
                  _ -> 0
                end)

              %Ethercoaster.Validator.SyncReward{
                epoch: epoch,
                validator_index: parse_int(index_str),
                reward: Enum.sum(slot_rewards)
              }
            else
              %Ethercoaster.Validator.SyncReward{
                epoch: epoch,
                validator_index: parse_int(index_str),
                reward: 0
              }
            end
          end,
          max_concurrency: max_concurrency,
          timeout: 60_000
        )
        |> Enum.flat_map(fn
          {:ok, reward} -> [reward]
          _ -> []
        end)

      {:ok, rewards}
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

  defp get_max_concurrency do
    :ethercoaster
    |> Application.get_env(Ethercoaster.BeaconChain, [])
    |> Keyword.get(:max_concurrency, 16)
  end

  defp parse_int(val) when is_integer(val), do: val
  defp parse_int(val) when is_binary(val), do: String.to_integer(val)
end
