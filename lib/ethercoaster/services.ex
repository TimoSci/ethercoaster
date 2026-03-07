defmodule Ethercoaster.Services do
  import Ecto.Query

  alias Ethercoaster.Repo
  alias Ethercoaster.Service
  alias Ethercoaster.Validators

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
          validator_records = Validators.resolve_inputs(validator_inputs)

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
    attrs =
      if service.status == "completed" do
        Map.put(attrs, :status, "modified")
      else
        attrs
      end

    Repo.transaction(fn ->
      changeset = Service.changeset(service, attrs)

      case Repo.update(changeset) do
        {:ok, service} ->
          validator_records = Validators.resolve_inputs(validator_inputs)

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

end
