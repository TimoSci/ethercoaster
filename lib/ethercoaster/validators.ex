defmodule Ethercoaster.Validators do
  import Ecto.Query

  require Logger

  alias Ethercoaster.Repo
  alias Ethercoaster.ValidatorRecord
  alias Ethercoaster.ValidatorGroup
  alias Ethercoaster.ValidatorSupergroup
  alias Ethercoaster.BeaconChain.Beacon

  def list_validators do
    ValidatorRecord
    |> order_by([v], desc: v.inserted_at, desc: v.id)
    |> preload(:state)
    |> Repo.all()
  end

  def list_validators_by_index do
    ValidatorRecord
    |> order_by([v], asc: v.index)
    |> preload(:state)
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

  @doc """
  Queries the beacon chain for the validator's current state and updates the record.
  Sets `exists` to true/false and `state_id` to the matching validator state.
  """
  def check_state(%ValidatorRecord{} = validator) do
    identifier =
      cond do
        is_binary(validator.public_key) and validator.public_key != "" -> validator.public_key
        is_integer(validator.index) -> Integer.to_string(validator.index)
        true -> nil
      end

    if is_nil(identifier) do
      {:error, "No public key or index to look up"}
    else
      case Beacon.get_validator("head", identifier) do
        {:ok, %{"status" => status} = data} ->
          state = Repo.get_by(Ethercoaster.ValidatorState, name: status)

          attrs = %{exists: true, state_id: state && state.id}

          # Also backfill missing index/pubkey while we're at it
          attrs = maybe_backfill(attrs, validator, data)

          update_validator(validator, attrs)

        {:error, %{status: 404}} ->
          update_validator(validator, %{exists: false, state_id: nil})

        {:error, reason} ->
          Logger.warning("Failed to check state for validator #{identifier}: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp maybe_backfill(attrs, validator, %{"index" => index_str, "validator" => %{"pubkey" => pubkey}}) do
    index = if is_binary(index_str), do: String.to_integer(index_str), else: index_str
    attrs = if is_nil(validator.index), do: Map.put(attrs, :index, index), else: attrs
    if is_nil(validator.public_key) or validator.public_key == "", do: Map.put(attrs, :public_key, pubkey), else: attrs
  end

  defp maybe_backfill(attrs, _validator, _data), do: attrs

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

  # --- Supergroups ---

  def list_supergroups do
    ValidatorSupergroup
    |> order_by([s], asc: s.name)
    |> preload([groups: :validators, children: []])
    |> Repo.all()
  end

  def get_supergroup!(id) do
    ValidatorSupergroup
    |> preload([groups: :validators, children: []])
    |> Repo.get!(id)
  end

  def create_supergroup(attrs) do
    %ValidatorSupergroup{}
    |> ValidatorSupergroup.changeset(attrs)
    |> Repo.insert()
  end

  def rename_supergroup(%ValidatorSupergroup{} = supergroup, attrs) do
    supergroup
    |> ValidatorSupergroup.changeset(attrs)
    |> Repo.update()
  end

  def delete_supergroup(id) do
    Repo.get!(ValidatorSupergroup, id) |> Repo.delete()
  end

  def add_group_to_supergroup(supergroup_id, group_id) do
    supergroup = get_supergroup!(supergroup_id)
    group = get_group!(group_id)

    existing_ids = MapSet.new(supergroup.groups, & &1.id)

    unless MapSet.member?(existing_ids, group.id) do
      groups = supergroup.groups ++ [group]

      supergroup
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:groups, groups)
      |> Repo.update!()
    end

    :ok
  end

  def remove_group_from_supergroup(supergroup_id, group_id) do
    supergroup = get_supergroup!(supergroup_id)
    groups = Enum.reject(supergroup.groups, &(&1.id == group_id))

    supergroup
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:groups, groups)
    |> Repo.update!()

    :ok
  end

  @doc """
  Adds a child supergroup to a parent supergroup.
  Returns {:error, :circular_reference} if this would create a cycle.
  """
  def add_child_supergroup(parent_id, child_id) do
    if parent_id == child_id do
      {:error, :circular_reference}
    else
      if ancestor_of?(child_id, parent_id) do
        {:error, :circular_reference}
      else
        parent = get_supergroup!(parent_id)
        child = get_supergroup!(child_id)

        existing_ids = MapSet.new(parent.children, & &1.id)

        unless MapSet.member?(existing_ids, child.id) do
          children = parent.children ++ [child]

          parent
          |> Ecto.Changeset.change()
          |> Ecto.Changeset.put_assoc(:children, children)
          |> Repo.update!()
        end

        :ok
      end
    end
  end

  def remove_child_supergroup(parent_id, child_id) do
    parent = get_supergroup!(parent_id)
    children = Enum.reject(parent.children, &(&1.id == child_id))

    parent
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:children, children)
    |> Repo.update!()

    :ok
  end

  @doc """
  Returns all unique validators across all groups and child supergroups (recursively).
  """
  def supergroup_validators(supergroup_id) do
    supergroup_validators(supergroup_id, MapSet.new())
  end

  defp supergroup_validators(supergroup_id, visited) do
    if MapSet.member?(visited, supergroup_id) do
      []
    else
      visited = MapSet.put(visited, supergroup_id)
      supergroup = get_supergroup!(supergroup_id)

      # Validators from direct groups (need to preload validators on groups)
      group_validators =
        supergroup.groups
        |> Enum.map(& get_group!(&1.id))
        |> Enum.flat_map(& &1.validators)

      # Validators from child supergroups (recursive)
      child_validators =
        supergroup.children
        |> Enum.flat_map(& supergroup_validators(&1.id, visited))

      (group_validators ++ child_validators)
      |> Enum.uniq_by(& &1.id)
    end
  end

  @doc """
  Checks if `potential_ancestor_id` is an ancestor of `supergroup_id`.
  Used to prevent circular references.
  """
  def ancestor_of?(potential_ancestor_id, supergroup_id) do
    ancestor_of?(potential_ancestor_id, supergroup_id, MapSet.new())
  end

  defp ancestor_of?(_potential_ancestor_id, _supergroup_id, visited)
       when map_size(visited) > 1000,
       do: true

  defp ancestor_of?(potential_ancestor_id, supergroup_id, visited) do
    if MapSet.member?(visited, supergroup_id) do
      false
    else
      visited = MapSet.put(visited, supergroup_id)
      supergroup = get_supergroup!(potential_ancestor_id)

      Enum.any?(supergroup.children, fn child ->
        child.id == supergroup_id or ancestor_of?(child.id, supergroup_id, visited)
      end)
    end
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
