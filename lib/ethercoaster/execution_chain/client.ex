defmodule Ethercoaster.ExecutionChain.Client do
  @moduledoc """
  JSON-RPC client for the Ethereum execution layer.

  Supports HTTP (http/https) endpoints via `Req` and WebSocket (ws/wss)
  endpoints via `Ethercoaster.ExecutionChain.WebSocket`.

  For WebSocket endpoints, set a connection PID with `put_ws_pid/1` in the
  calling process. `call/2` and `batch/1` automatically route through it.
  """

  alias Ethercoaster.ExecutionChain.{Error, WebSocket}

  @base_url_key :execution_chain_base_url
  @ws_pid_key :execution_chain_ws_pid

  # --- Per-process state ---

  @doc "Sets a per-process base URL override for execution layer calls."
  def put_base_url(nil), do: :ok
  def put_base_url(url), do: Process.put(@base_url_key, url)

  @doc "Returns the current per-process base URL override, or nil."
  def get_base_url, do: Process.get(@base_url_key)

  @doc "Sets a per-process WebSocket PID for routing calls over WebSocket."
  def put_ws_pid(nil), do: :ok
  def put_ws_pid(pid) when is_pid(pid), do: Process.put(@ws_pid_key, pid)

  @doc "Returns the current per-process WebSocket PID, or nil."
  def get_ws_pid, do: Process.get(@ws_pid_key)

  @doc "Returns true if the given URL uses a WebSocket scheme (ws:// or wss://)."
  def ws_scheme?(nil), do: false
  def ws_scheme?(url), do: String.starts_with?(url, "ws://") or String.starts_with?(url, "wss://")

  # --- Public API ---

  @doc "Sends a JSON-RPC call. Routes through WebSocket if a ws PID is set."
  @spec call(String.t(), list()) :: {:ok, term()} | {:error, Error.t()}
  def call(method, params \\ []) do
    case Process.get(@ws_pid_key) do
      pid when is_pid(pid) ->
        try do
          WebSocket.call(pid, method, params)
        catch
          :exit, _ -> {:error, %Error{message: "WebSocket connection lost"}}
        end

      nil ->
        http_call(method, params)
    end
  end

  @doc "Sends a batch of JSON-RPC calls. Sequential over WebSocket, single POST over HTTP."
  @spec batch([{String.t(), list()}]) :: [{:ok, term()} | {:error, Error.t()}]
  def batch(calls) do
    case Process.get(@ws_pid_key) do
      pid when is_pid(pid) ->
        Enum.map(calls, fn {method, params} ->
          try do
            WebSocket.call(pid, method, params)
          catch
            :exit, _ -> {:error, %Error{message: "WebSocket connection lost"}}
          end
        end)

      nil ->
        http_batch(calls)
    end
  end

  # --- HTTP implementation ---

  defp http_call(method, params) do
    body = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => method,
      "params" => params
    }

    new()
    |> Req.post(json: body)
    |> handle_response()
  end

  defp http_batch(calls) do
    body =
      calls
      |> Enum.with_index(1)
      |> Enum.map(fn {{method, params}, id} ->
        %{"jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params}
      end)

    case Req.post(new(), json: body) do
      {:ok, %Req.Response{status: status, body: results}} when status in 200..299 and is_list(results) ->
        results
        |> Enum.sort_by(& &1["id"])
        |> Enum.map(&unwrap_result/1)

      {:ok, %Req.Response{status: status}} ->
        List.duplicate({:error, %Error{message: "HTTP #{status}"}}, length(calls))

      {:error, exception} ->
        err = {:error, %Error{message: "request failed: #{Exception.message(exception)}"}}
        List.duplicate(err, length(calls))
    end
  end

  defp new do
    config = Application.get_env(:ethercoaster, Ethercoaster.ExecutionChain, [])

    base_url = Process.get(@base_url_key) || Keyword.get(config, :base_url, "http://localhost:8545")
    receive_timeout = Keyword.get(config, :receive_timeout, 15_000)
    req_options = Keyword.get(config, :req_options, [])

    [base_url: base_url, receive_timeout: receive_timeout, finch: Ethercoaster.Finch]
    |> Keyword.merge(req_options)
    |> Req.new()
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}})
       when status in 200..299 do
    unwrap_result(body)
  end

  defp handle_response({:ok, %Req.Response{status: status}}) do
    {:error, %Error{message: "HTTP #{status}"}}
  end

  defp handle_response({:error, %Req.TransportError{reason: reason}}) do
    {:error, %Error{message: "transport error: #{inspect(reason)}"}}
  end

  defp handle_response({:error, exception}) do
    {:error, %Error{message: "request failed: #{Exception.message(exception)}"}}
  end

  defp unwrap_result(%{"result" => result}), do: {:ok, result}

  defp unwrap_result(%{"error" => %{"code" => code, "message" => message}}) do
    {:error, %Error{code: code, message: message}}
  end

  defp unwrap_result(_), do: {:error, %Error{message: "unexpected response format"}}
end
