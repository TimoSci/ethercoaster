defmodule Ethercoaster.Validators do
  import Ecto.Query

  alias Ethercoaster.Repo
  alias Ethercoaster.ValidatorRecord

  def list_validators do
    ValidatorRecord
    |> order_by([v], desc: v.inserted_at, desc: v.id)
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
              Repo.insert!(%ValidatorRecord{public_key: input, index: 0},
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
              Repo.insert!(%ValidatorRecord{public_key: "unresolved:#{index}", index: index},
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
