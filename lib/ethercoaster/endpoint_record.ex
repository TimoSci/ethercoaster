defmodule Ethercoaster.EndpointRecord do
  use Ecto.Schema
  import Ecto.Changeset

  schema "endpoints" do
    field :address, :string
    field :port, :integer

    timestamps(type: :utc_datetime)
  end

  def changeset(endpoint, attrs) do
    endpoint
    |> cast(attrs, [:address, :port])
    |> validate_required([:address, :port])
    |> validate_number(:port, greater_than: 0, less_than: 65536)
    |> unique_constraint([:address, :port])
  end

  def url(%__MODULE__{address: address, port: port}) do
    "#{address}:#{port}"
  end

  def parse_url(url) when is_binary(url) do
    url = String.trim(url)

    case URI.parse(url) do
      %URI{scheme: scheme, host: host, port: port} when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        default_port = if scheme == "https", do: 443, else: 80
        {:ok, %{address: "#{scheme}://#{host}", port: port || default_port}}

      _ ->
        {:error, "Invalid endpoint URL"}
    end
  end
end
