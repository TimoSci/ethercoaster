defmodule Ethercoaster.Endpoints do
  import Ecto.Query

  alias Ethercoaster.Repo
  alias Ethercoaster.EndpointRecord

  def list_endpoints do
    EndpointRecord
    |> order_by([e], asc: e.address, asc: e.port)
    |> Repo.all()
  end

  def get_endpoint!(id) do
    Repo.get!(EndpointRecord, id)
  end

  def create_endpoint(attrs) do
    %EndpointRecord{}
    |> EndpointRecord.changeset(attrs)
    |> Repo.insert()
  end

  def update_endpoint(endpoint, attrs) do
    endpoint
    |> EndpointRecord.changeset(attrs)
    |> Repo.update()
  end

  def delete_endpoint(id) do
    EndpointRecord
    |> Repo.get!(id)
    |> Repo.delete()
  end

  @doc """
  Ensures an endpoint exists for the given URL. Returns :ok or :error.
  """
  def ensure_from_url(url) when is_binary(url) do
    case EndpointRecord.parse_url(url) do
      {:ok, attrs} ->
        case Repo.get_by(EndpointRecord, address: attrs.address, port: attrs.port) do
          nil -> create_endpoint(attrs)
          existing -> {:ok, existing}
        end

      {:error, _} = err ->
        err
    end
  end
end
