defmodule Ethercoaster.Validators do
  import Ecto.Query

  require Logger

  alias Ethercoaster.Repo
  alias Ethercoaster.ValidatorRecord
  alias Ethercoaster.ValidatorGroup
  alias Ethercoaster.BeaconChain.Beacon

  def list_validators do
    ValidatorRecord
    |> order_by([v], desc: v.inserted_at, desc: v.id)
    |> Repo.all()
  end

  def list_validators_by_index do
    ValidatorRecord
    |> order_by([v], asc: v.index)
    |> Repo.all()
  end

  def get_validator!(id), do: Repo.get!(ValidatorRecord, id)

  def create_validator(attrs) do
    %ValidatorRecord{}
    |> ValidatorRecord.changeset(attrs)
    |> Repo.insert()
  end

  def update_validator(%ValidatorRecord{} = validator, attrs) do
    validator
    |> ValidatorRecord.changeset(attrs)
    |> Repo.update()
  end

  def delete_validator(id) do
    Repo.get!(ValidatorRecord, id) |> Repo.delete()
  end

  @doc """
  Resolves missing index or public_key for a validator by querying the beacon chain API.
  Returns the updated validator record, or the original if the lookup fails.
  """
  def resolve_from_beacon(%ValidatorRecord{} = validator) do
    identifier =
      cond do
        is_binary(validator.public_key) and validator.public_key != "" -> validator.public_key
        is_integer(validator.index) -> Integer.to_string(validator.index)
        true -> nil
      end

    if identifier do
      case Beacon.get_validator("head", identifier) do
        {:ok, %{"index" => index_str, "validator" => %{"pubkey" => pubkey}}} ->
          index = if is_binary(index_str), do: String.to_integer(index_str), else: index_str
          attrs = %{}
          attrs = if is_nil(validator.index), do: Map.put(attrs, :index, index), else: attrs
          attrs = if is_nil(validator.public_key) or validator.public_key == "", do: Map.put(attrs, :public_key, pubkey), else: attrs

          if attrs != %{} do
            case update_validator(validator, attrs) do
              {:ok, updated} -> updated
              {:error, _} -> validator
            end
          else
            validator
          end

        {:error, reason} ->
          Logger.warning("Failed to resolve validator #{identifier}: #{inspect(reason)}")
          validator
      end
    else
      validator
    end
  end

  # --- Groups ---

  def list_groups do
    ValidatorGroup
    |> order_by([g], asc: g.name)
    |> preload(:validators)
    |> Repo.all()
  end

  def get_group!(id) do
    ValidatorGroup
    |> preload(:validators)
    |> Repo.get!(id)
  end

  def create_group(attrs) do
    %ValidatorGroup{}
    |> ValidatorGroup.changeset(attrs)
    |> Repo.insert()
  end

  def rename_group(%ValidatorGroup{} = group, attrs) do
    group
    |> ValidatorGroup.changeset(attrs)
    |> Repo.update()
  end

  def delete_group(id) do
    Repo.get!(ValidatorGroup, id) |> Repo.delete()
  end

  def add_to_group(group_id, validator_id) do
    group = get_group!(group_id)
    validator = get_validator!(validator_id)

    existing_ids = MapSet.new(group.validators, & &1.id)

    unless MapSet.member?(existing_ids, validator.id) do
      validators = group.validators ++ [validator]

      group
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:validators, validators)
      |> Repo.update!()
    end

    :ok
  end

  def remove_from_group(group_id, validator_id) do
    group = get_group!(group_id)
    validators = Enum.reject(group.validators, &(&1.id == validator_id))

    group
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:validators, validators)
    |> Repo.update!()

    :ok
  end

  @doc """
  Resolves a list of validator input strings (public keys or indices) into ValidatorRecord structs.
  Creates records if they don't exist.
  """
  def resolve_inputs(inputs) do
    inputs
    |> Enum.map(fn input ->
      input = String.trim(input)

      cond do
        String.match?(input, ~r/\A0x[0-9a-fA-F]{96}\z/) ->
          case Repo.get_by(ValidatorRecord, public_key: input) do
            %ValidatorRecord{} = record ->
              record

            nil ->
              Repo.insert!(%ValidatorRecord{public_key: input, index: nil},
                on_conflict: :nothing,
                conflict_target: :public_key
              )

              Repo.get_by!(ValidatorRecord, public_key: input)
          end

        String.match?(input, ~r/\A\d+\z/) ->
          index = String.to_integer(input)

          case Repo.get_by(ValidatorRecord, index: index) do
            %ValidatorRecord{} = record ->
              record

            nil ->
              Repo.insert!(%ValidatorRecord{public_key: nil, index: index},
                on_conflict: :nothing,
                conflict_target: :index
              )

              Repo.get_by!(ValidatorRecord, index: index)
          end

        true ->
          raise "Invalid validator input: #{input}"
      end
    end)
    |> Enum.uniq_by(& &1.id)
  end
end
