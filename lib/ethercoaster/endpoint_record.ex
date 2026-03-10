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
    uri = URI.parse(address)
    default_port = if uri.scheme == "https", do: 443, else: 80

    if port == default_port do
      address
    else
      "#{uri.scheme}://#{uri.host}:#{port}#{uri.path}"
    end
  end

  def parse_url(url) when is_binary(url) do
    url = String.trim(url)

    case URI.parse(url) do
      %URI{scheme: scheme, host: host, port: port, path: path}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        default_port = if scheme == "https", do: 443, else: 80
        clean_path = if path in [nil, "/"], do: "", else: String.trim_trailing(path, "/")
        {:ok, %{address: "#{scheme}://#{host}#{clean_path}", port: port || default_port}}

      _ ->
        {:error, "Invalid endpoint URL"}
    end
  end
end
