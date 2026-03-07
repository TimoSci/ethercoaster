defmodule Ethercoaster.Services do
  import Ecto.Query

  alias Ethercoaster.Repo
  alias Ethercoaster.Service
  alias Ethercoaster.ValidatorRecord

  def list_services do
    Service
    |> order_by([s], desc: s.inserted_at, desc: s.id)
    |> preload(:validators)
    |> Repo.all()
  end

  def get_service!(id) do
    Service
    |> preload(:validators)
    |> Repo.get!(id)
  end

  def create_service(attrs, validator_inputs) do
    Repo.transaction(fn ->
      changeset = Service.changeset(%Service{}, attrs)

      case Repo.insert(changeset) do
        {:ok, service} ->
          validator_records = resolve_validators(validator_inputs)

          service
          |> Repo.preload(:validators)
          |> Ecto.Changeset.change()
          |> Ecto.Changeset.put_assoc(:validators, validator_records)
          |> Repo.update!()

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  def update_service_status(service_id, status) do
    Service
    |> Repo.get!(service_id)
    |> Ecto.Changeset.change(status: status)
    |> Repo.update!()
  end

  def update_service(service, attrs, validator_inputs) do
    Repo.transaction(fn ->
      changeset = Service.changeset(service, attrs)

      case Repo.update(changeset) do
        {:ok, service} ->
          validator_records = resolve_validators(validator_inputs)

          service
          |> Repo.preload(:validators)
          |> Ecto.Changeset.change()
          |> Ecto.Changeset.put_assoc(:validators, validator_records)
          |> Repo.update!()

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  def delete_service(id) do
    Service
    |> Repo.get!(id)
    |> Repo.delete()
  end

  defp resolve_validators(inputs) do
    Enum.map(inputs, fn input ->
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
