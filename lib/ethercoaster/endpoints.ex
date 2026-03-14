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

  Consensus endpoints are tested via `GET /eth/v1/node/health`.
  Execution endpoints are tested via HTTP JSON-RPC (`eth_chainId`) for
  `http://` URLs or via WebSocket for `ws://` URLs.

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

  defp test_execution("ws://" <> _ = url), do: test_execution_ws(url)
  defp test_execution("wss://" <> _ = url), do: test_execution_ws(url)

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

  defp test_execution_ws(url) do
    uri = URI.parse(url)
    ws_scheme = if uri.scheme == "wss", do: :wss, else: :ws
    http_scheme = if ws_scheme == :wss, do: :https, else: :http
    port = uri.port || if(ws_scheme == :wss, do: 443, else: 80)
    path = uri.path || "/"

    with {:ok, conn} <- Mint.HTTP.connect(http_scheme, uri.host, port, protocols: [:http1]),
         {:ok, conn, ref} <- Mint.WebSocket.upgrade(ws_scheme, conn, path, []),
         {:ok, conn, websocket} <- await_upgrade(conn, ref),
         {:ok, conn, websocket} <- ws_send(conn, ref, websocket, "eth_chainId"),
         {:ok, _conn, response} <- ws_receive(conn, ref, websocket) do
      case response do
        %{"result" => result} ->
          {:ok, "WebSocket connected\n\neth_chainId: #{result}"}

        %{"error" => %{"message" => msg}} ->
          {:error_response, "WebSocket connected\n\nRPC error: #{msg}"}

        other ->
          {:error_response, "WebSocket connected\n\nUnexpected: #{inspect(other)}"}
      end
    else
      {:error, reason} ->
        {:unreachable, "Connection failed: #{inspect(reason)}"}

      {:error, _conn, reason} ->
        {:unreachable, "Connection failed: #{inspect(reason)}"}
    end
  end

  defp await_upgrade(conn, ref) do
    receive do
      message ->
        case Mint.WebSocket.stream(conn, message) do
          {:ok, conn, responses} ->
            {status, headers} =
              Enum.reduce(responses, {nil, []}, fn
                {:status, ^ref, s}, {_, h} -> {s, h}
                {:headers, ^ref, h}, {s, acc} -> {s, acc ++ h}
                {:done, ^ref}, acc -> acc
                _, acc -> acc
              end)

            if status do
              Mint.WebSocket.new(conn, ref, status, headers)
            else
              {:error, conn, :upgrade_incomplete}
            end

          {:error, conn, reason, _} ->
            {:error, conn, reason}

          :unknown ->
            {:error, conn, :unknown_message}
        end
    after
      5000 -> {:error, conn, :timeout}
    end
  end

  defp ws_send(conn, ref, websocket, method) do
    payload = Jason.encode!(%{"jsonrpc" => "2.0", "id" => 1, "method" => method, "params" => []})

    case Mint.WebSocket.encode(websocket, {:text, payload}) do
      {:ok, websocket, data} ->
        case Mint.WebSocket.stream_request_body(conn, ref, data) do
          {:ok, conn} -> {:ok, conn, websocket}
          {:error, conn, reason} -> {:error, conn, reason}
        end

      {:error, _websocket, reason} ->
        {:error, conn, reason}
    end
  end

  defp ws_receive(conn, ref, websocket) do
    receive do
      message ->
        case Mint.WebSocket.stream(conn, message) do
          {:ok, conn, responses} ->
            data =
              Enum.find_value(responses, fn
                {:data, ^ref, d} -> d
                _ -> nil
              end)

            if data do
              case Mint.WebSocket.decode(websocket, data) do
                {:ok, _websocket, frames} ->
                  text =
                    Enum.find_value(frames, fn
                      {:text, t} -> t
                      _ -> nil
                    end)

                  if text do
                    {:ok, conn, Jason.decode!(text)}
                  else
                    {:ok, conn, %{"error" => %{"message" => "no text frame"}}}
                  end

                {:error, _websocket, reason} ->
                  {:error, conn, reason}
              end
            else
              # No data yet, try again
              ws_receive(conn, ref, websocket)
            end

          {:error, conn, reason, _} ->
            {:error, conn, reason}

          :unknown ->
            ws_receive(conn, ref, websocket)
        end
    after
      5000 -> {:error, conn, :timeout}
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
