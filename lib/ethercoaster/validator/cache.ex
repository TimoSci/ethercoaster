defmodule Ethercoaster.Validator.Cache do
  @moduledoc """
  Caches validator reward data in the transactions table.
  Tracks which (validator, epoch, category) combinations have been fetched
  via the cached_epochs table.
  """

  import Ecto.Query

  alias Ethercoaster.Repo
  alias Ethercoaster.{CachedEpoch, Transaction, TransactionType, ValidatorRecord}
  alias Ethercoaster.Validator.{ProposalReward, SyncReward}

  @slots_per_epoch 32
  @seconds_per_slot 12
  @seconds_per_epoch @slots_per_epoch * @seconds_per_slot

  # --- Validator record ---

  def find_or_create_validator!(pubkey, index) do
    case Repo.get_by(ValidatorRecord, public_key: pubkey) do
      %ValidatorRecord{} = record ->
        record

      nil ->
        Repo.insert!(
          %ValidatorRecord{public_key: pubkey, index: index},
          on_conflict: :nothing,
          conflict_target: :public_key
        )

        Repo.get_by!(ValidatorRecord, public_key: pubkey)
    end
  end

  # --- Cache queries ---

  def get_cached_epoch_set(validator_id, from_epoch, to_epoch, category) do
    CachedEpoch
    |> where([c], c.validator_id == ^validator_id)
    |> where([c], c.epoch >= ^from_epoch and c.epoch <= ^to_epoch)
    |> where([c], c.category == ^category)
    |> select([c], c.epoch)
    |> Repo.all()
    |> MapSet.new()
  end

  def clear_cache(validator_id, epochs, category) do
    epoch_list = Enum.to_list(epochs)
    type_ids = get_type_ids(type_names_for(category)) |> Map.values()

    Transaction
    |> where([t], t.validator_id == ^validator_id)
    |> where([t], t.epoch in ^epoch_list)
    |> where([t], t.type_id in ^type_ids)
    |> Repo.delete_all()

    CachedEpoch
    |> where([c], c.validator_id == ^validator_id)
    |> where([c], c.epoch in ^epoch_list)
    |> where([c], c.category == ^category)
    |> Repo.delete_all()
  end

  # --- Load from cache ---

  def load_category(:attestation, validator_id, epochs, _validator_index) do
    type_names = type_names_for("attestation")
    epoch_list = MapSet.to_list(epochs)

    Transaction
    |> join(:inner, [t], tt in TransactionType, on: t.type_id == tt.id)
    |> where([t, _tt], t.validator_id == ^validator_id)
    |> where([t, _tt], t.epoch in ^epoch_list)
    |> where([_t, tt], tt.name in ^type_names)
    |> select([t, tt], %{epoch: t.epoch, name: tt.name, amount: t.amount})
    |> Repo.all()
    |> Enum.group_by(& &1.epoch)
    |> Enum.map(fn {epoch, txns} ->
      amounts = Map.new(txns, &{&1.name, decimal_to_int(&1.amount)})

      %{
        epoch: epoch,
        head: amounts["Head reward"] || 0,
        target: amounts["Target reward"] || 0,
        source: amounts["Source reward"] || 0,
        inactivity: amounts["Inactivity penalty"] || 0
      }
    end)
  end

  def load_category(:sync_committee, validator_id, epochs, validator_index) do
    epoch_list = MapSet.to_list(epochs)

    Transaction
    |> join(:inner, [t], tt in TransactionType, on: t.type_id == tt.id)
    |> where([t, _tt], t.validator_id == ^validator_id)
    |> where([t, _tt], t.epoch in ^epoch_list)
    |> where([_t, tt], tt.name == "Sync committee rewards")
    |> select([t, _tt], %{epoch: t.epoch, amount: t.amount})
    |> Repo.all()
    |> Enum.map(fn row ->
      %SyncReward{
        epoch: row.epoch,
        validator_index: validator_index,
        reward: decimal_to_int(row.amount)
      }
    end)
  end

  def load_category(:block_proposal, validator_id, epochs, validator_index) do
    epoch_list = MapSet.to_list(epochs)

    Transaction
    |> join(:inner, [t], tt in TransactionType, on: t.type_id == tt.id)
    |> where([t, _tt], t.validator_id == ^validator_id)
    |> where([t, _tt], t.epoch in ^epoch_list)
    |> where([_t, tt], tt.name == "Consensus proposal reward")
    |> select([t, _tt], %{epoch: t.epoch, slot: t.slot, amount: t.amount})
    |> Repo.all()
    |> Enum.map(fn row ->
      %ProposalReward{
        epoch: row.epoch,
        slot: row.slot,
        validator_index: validator_index,
        total: decimal_to_int(row.amount)
      }
    end)
  end

  # --- Store to cache ---

  def store_and_mark(:attestation, validator_id, data, epochs, genesis_time) do
    required = type_names_for("attestation")
    type_ids = get_type_ids(required)
    if map_size(type_ids) < length(required), do: throw(:skip)

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows =
      Enum.flat_map(data, fn entry ->
        datetime = epoch_to_datetime(entry.epoch, genesis_time)

        [
          {:head, "Head reward"},
          {:target, "Target reward"},
          {:source, "Source reward"},
          {:inactivity, "Inactivity penalty"}
        ]
        |> Enum.map(fn {field, type_name} ->
          %{
            amount: Decimal.new(Map.get(entry, field, 0)),
            datetime: datetime,
            epoch: entry.epoch,
            slot: nil,
            type_id: type_ids[type_name],
            validator_id: validator_id,
            inserted_at: now,
            updated_at: now
          }
        end)
      end)

    if rows != [], do: Repo.insert_all(Transaction, rows, on_conflict: :nothing)
    mark_cached(validator_id, epochs, "attestation", now)
  catch
    :skip -> :ok
  end

  def store_and_mark(:sync_committee, validator_id, data, epochs, genesis_time) do
    type_ids = get_type_ids(["Sync committee rewards"])
    if map_size(type_ids) < 1, do: throw(:skip)

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows =
      Enum.map(data, fn entry ->
        %{
          amount: Decimal.new(entry.reward),
          datetime: epoch_to_datetime(entry.epoch, genesis_time),
          epoch: entry.epoch,
          slot: nil,
          type_id: type_ids["Sync committee rewards"],
          validator_id: validator_id,
          inserted_at: now,
          updated_at: now
        }
      end)

    if rows != [], do: Repo.insert_all(Transaction, rows, on_conflict: :nothing)
    mark_cached(validator_id, epochs, "sync_committee", now)
  catch
    :skip -> :ok
  end

  def store_and_mark(:block_proposal, validator_id, data, epochs, genesis_time) do
    type_ids = get_type_ids(["Consensus proposal reward"])
    if map_size(type_ids) < 1, do: throw(:skip)

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows =
      Enum.map(data, fn entry ->
        %{
          amount: Decimal.new(entry.total),
          datetime: epoch_to_datetime(entry.epoch, genesis_time),
          epoch: entry.epoch,
          slot: entry.slot,
          type_id: type_ids["Consensus proposal reward"],
          validator_id: validator_id,
          inserted_at: now,
          updated_at: now
        }
      end)

    if rows != [], do: Repo.insert_all(Transaction, rows, on_conflict: :nothing)
    mark_cached(validator_id, epochs, "block_proposal", now)
  catch
    :skip -> :ok
  end

  # --- Helpers ---

  defp mark_cached(validator_id, epochs, category, now) do
    epoch_list = Enum.to_list(epochs)

    rows =
      Enum.map(epoch_list, fn epoch ->
        %{
          validator_id: validator_id,
          epoch: epoch,
          category: category,
          inserted_at: now,
          updated_at: now
        }
      end)

    if rows != [] do
      Repo.insert_all(CachedEpoch, rows, on_conflict: :nothing)
    end
  end

  defp type_names_for("attestation"),
    do: ["Head reward", "Target reward", "Source reward", "Inactivity penalty"]

  defp type_names_for("sync_committee"),
    do: ["Sync committee rewards"]

  defp type_names_for("block_proposal"),
    do: ["Consensus proposal reward"]

  defp get_type_ids(names) do
    TransactionType
    |> where([t], t.name in ^names)
    |> select([t], {t.name, t.id})
    |> Repo.all()
    |> Map.new()
  end

  defp decimal_to_int(%Decimal{} = d), do: Decimal.to_integer(d)
  defp decimal_to_int(val) when is_integer(val), do: val

  defp epoch_to_datetime(epoch, genesis_time) do
    (genesis_time + epoch * @seconds_per_epoch)
    |> DateTime.from_unix!()
  end
end
