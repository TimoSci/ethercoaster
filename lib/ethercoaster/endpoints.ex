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
  def ensure_from_url(url, chaintype \\ :consensus) when is_binary(url) do
    case EndpointRecord.parse_url(url) do
      {:ok, attrs} ->
        case Repo.get_by(EndpointRecord, address: attrs.address, port: attrs.port) do
          nil -> create_endpoint(Map.put(attrs, :chaintype, chaintype))
          existing -> {:ok, existing}
        end

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Tests connectivity to an endpoint by sending a health/status request.

  Uses `/eth/v1/node/health` for consensus endpoints and `eth_chainId`
  JSON-RPC for execution endpoints.

  Returns `{status, log}` where status is `:ok`, `:error_response`, or `:unreachable`,
  and log is a string with the response details.
  """
  @spec test_endpoint(EndpointRecord.t()) :: {:ok | :error_response | :unreachable, String.t()}
  def test_endpoint(%EndpointRecord{} = endpoint) do
    url = EndpointRecord.url(endpoint)

    try do
      case endpoint.chaintype do
        :consensus -> test_consensus(url)
        :execution -> test_execution(url)
      end
    rescue
      e -> {:unreachable, "Error: #{Exception.message(e)}"}
    end
  end

  defp test_consensus(url) do
    case Req.get(url <> "/eth/v1/node/health",
           receive_timeout: 5000,
           connect_options: [timeout: 5000],
           retry: false
         ) do
      {:ok, %{status: status, headers: headers, body: body}} ->
        kind = if status in 200..299, do: :ok, else: :error_response
        {kind, format_response(status, headers, body)}

      {:error, %Req.TransportError{reason: reason}} ->
        {:unreachable, "Connection failed: #{inspect(reason)}"}

      {:error, error} ->
        {:unreachable, "Request failed: #{inspect(error)}"}
    end
  end

  defp test_execution(url) do
    body = %{"jsonrpc" => "2.0", "id" => 1, "method" => "eth_chainId", "params" => []}

    case Req.post(url,
           json: body,
           receive_timeout: 5000,
           connect_options: [timeout: 5000],
           retry: false
         ) do
      {:ok, %{status: status, headers: headers, body: resp_body}} ->
        kind =
          cond do
            status not in 200..299 -> :error_response
            is_map(resp_body) and Map.has_key?(resp_body, "error") -> :error_response
            is_map(resp_body) and Map.has_key?(resp_body, "result") -> :ok
            true -> :error_response
          end

        {kind, format_response(status, headers, resp_body)}

      {:error, %Req.TransportError{reason: reason}} ->
        {:unreachable, "Connection failed: #{inspect(reason)}"}

      {:error, error} ->
        {:unreachable, "Request failed: #{inspect(error)}"}
    end
  end

  defp format_response(status, headers, body) do
    header_lines =
      headers
      |> Enum.map(fn {k, v} -> "#{k}: #{v}" end)
      |> Enum.join("\n")

    body_str =
      case body do
        b when is_binary(b) -> b
        b when is_map(b) or is_list(b) -> Jason.encode!(b, pretty: true)
        b -> inspect(b)
      end

    "HTTP #{status}\n#{header_lines}\n\n#{body_str}"
  end
end
