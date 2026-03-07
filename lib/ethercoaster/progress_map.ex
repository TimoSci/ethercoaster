defmodule Ethercoaster.ProgressMap do
  @moduledoc """
  Scans cached_epochs to determine coverage for each validator/date/category combination.
  """

  import Ecto.Query

  alias Ethercoaster.Repo
  alias Ethercoaster.CachedEpoch

  @slots_per_epoch 32
  @seconds_per_slot 12
  @seconds_per_epoch @slots_per_epoch * @seconds_per_slot

  # Mainnet genesis time fallback
  @default_genesis_time 1_606_824_023

  @doc """
  Returns a nested map: %{validator_id => %{date_string => :full | :partial | :none}}
  """
  def scan(validators, date_strings, categories) when categories != [] do
    genesis_time = get_genesis_time()

    # Build a map of {date_string => {from_epoch, to_epoch}} for each date
    date_epoch_ranges =
      Map.new(date_strings, fn date_str ->
        {:ok, date} = Date.from_iso8601(date_str)
        from_epoch = date_to_first_epoch(date, genesis_time)
        to_epoch = date_to_last_epoch(date, genesis_time)
        {date_str, {from_epoch, to_epoch}}
      end)

    # Global epoch range
    all_ranges = Map.values(date_epoch_ranges)
    global_from = all_ranges |> Enum.map(&elem(&1, 0)) |> Enum.min()
    global_to = all_ranges |> Enum.map(&elem(&1, 1)) |> Enum.max()

    validator_ids = Enum.map(validators, & &1.id)

    # Query all cached epochs in the global range for all validators and categories
    cached =
      CachedEpoch
      |> where([c], c.validator_id in ^validator_ids)
      |> where([c], c.epoch >= ^global_from and c.epoch <= ^global_to)
      |> where([c], c.category in ^categories)
      |> select([c], {c.validator_id, c.epoch, c.category})
      |> Repo.all()

    # Group by validator_id: %{vid => MapSet of {epoch, category}}
    cached_by_validator =
      Enum.group_by(cached, &elem(&1, 0), fn {_, epoch, cat} -> {epoch, cat} end)
      |> Map.new(fn {vid, pairs} -> {vid, MapSet.new(pairs)} end)

    # For each validator and date, check coverage
    Map.new(validator_ids, fn vid ->
      cached_set = Map.get(cached_by_validator, vid, MapSet.new())

      date_map =
        Map.new(date_strings, fn date_str ->
          {from_epoch, to_epoch} = Map.fetch!(date_epoch_ranges, date_str)
          status = check_coverage(cached_set, from_epoch, to_epoch, categories)
          {date_str, status}
        end)

      {vid, date_map}
    end)
  end

  def scan(_validators, _date_strings, []), do: %{}

  defp check_coverage(cached_set, from_epoch, to_epoch, categories) do
    total = (to_epoch - from_epoch + 1) * length(categories)
    if total <= 0, do: throw(:none)

    count =
      Enum.count(from_epoch..to_epoch, fn epoch ->
        Enum.all?(categories, fn cat ->
          MapSet.member?(cached_set, {epoch, cat})
        end)
      end)

    cond do
      count == to_epoch - from_epoch + 1 -> :full
      count > 0 -> :partial
      true -> :none
    end
  catch
    :none -> :none
  end

  defp date_to_first_epoch(date, genesis_time) do
    {:ok, dt} = NaiveDateTime.new(date, ~T[00:00:00])
    {:ok, dt} = DateTime.from_naive(dt, "Etc/UTC")
    unix = DateTime.to_unix(dt)
    max(div(unix - genesis_time, @seconds_per_epoch), 0)
  end

  defp date_to_last_epoch(date, genesis_time) do
    {:ok, dt} = NaiveDateTime.new(date, ~T[23:59:59])
    {:ok, dt} = DateTime.from_naive(dt, "Etc/UTC")
    unix = DateTime.to_unix(dt)
    max(div(unix - genesis_time, @seconds_per_epoch), 0)
  end

  defp get_genesis_time do
    case Ethercoaster.BeaconChain.Beacon.get_genesis() do
      {:ok, %{"genesis_time" => gt}} when is_binary(gt) -> String.to_integer(gt)
      {:ok, %{"genesis_time" => gt}} when is_integer(gt) -> gt
      _ -> @default_genesis_time
    end
  end
end
