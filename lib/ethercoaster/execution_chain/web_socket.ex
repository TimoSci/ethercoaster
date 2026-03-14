defmodule Ethercoaster.ExecutionChain.WebSocket do
  @moduledoc """
  WebSocket JSON-RPC client for the Ethereum execution layer.

  Maintains a persistent WebSocket connection to an execution layer node
  (typically on port 8546) and supports subscriptions via `eth_subscribe`.

  ## Usage

      {:ok, pid} = WebSocket.start_link(url: "ws://localhost:8546")

      # One-off RPC call over WebSocket
      {:ok, block_number} = WebSocket.call(pid, "eth_blockNumber")

      # Subscribe to new heads
      {:ok, sub_id} = WebSocket.subscribe(pid, "newHeads")
      # Subscription events arrive as messages:
      #   {:eth_subscription, ^sub_id, data}
  """

  use GenServer

  require Logger

  alias Ethercoaster.ExecutionChain.Error

  defstruct [
    :conn,
    :websocket,
    :ref,
    :url,
    :upgrade_status,
    :upgrade_headers,
    caller_map: %{},
    sub_map: %{},
    next_id: 1
  ]

  @doc """
  Starts a WebSocket connection to the given URL.

  Options:
    * `:url` — WebSocket URL (default from config or `"ws://localhost:8546"`)
    * `:name` — optional GenServer name
  """
  def start_link(opts \\ []) do
    {url, gen_opts} = parse_opts(opts)
    GenServer.start_link(__MODULE__, url, gen_opts)
  end

  @doc """
  Starts a WebSocket connection without linking to the calling process.
  """
  def start(opts \\ []) do
    {url, gen_opts} = parse_opts(opts)
    GenServer.start(__MODULE__, url, gen_opts)
  end

  defp parse_opts(opts) do
    config = Application.get_env(:ethercoaster, Ethercoaster.ExecutionChain, [])
    url = Keyword.get(opts, :url) || Keyword.get(config, :ws_url, "ws://localhost:8546")
    name = Keyword.get(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    {url, gen_opts}
  end

  @doc """
  Sends a JSON-RPC call over the WebSocket and waits for the response.
  """
  @spec call(GenServer.server(), String.t(), list(), timeout()) ::
          {:ok, term()} | {:error, Error.t()}
  def call(pid, method, params \\ [], timeout \\ 15_000) do
    GenServer.call(pid, {:rpc_call, method, params}, timeout)
  end

  @doc """
  Subscribes to an event via `eth_subscribe`. Subscription messages will be
  sent to the calling process as `{:eth_subscription, subscription_id, data}`.
  """
  @spec subscribe(GenServer.server(), String.t(), list()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def subscribe(pid, event, params \\ []) do
    GenServer.call(pid, {:subscribe, event, params, self()})
  end

  @doc """
  Unsubscribes from a subscription.
  """
  @spec unsubscribe(GenServer.server(), String.t()) :: {:ok, boolean()} | {:error, Error.t()}
  def unsubscribe(pid, sub_id) do
    GenServer.call(pid, {:unsubscribe, sub_id})
  end

  # --- GenServer callbacks ---

  @impl true
  def init(url) do
    uri = URI.parse(url)
    ws_scheme = if uri.scheme in ["wss", "https"], do: :wss, else: :ws
    http_scheme = if ws_scheme == :wss, do: :https, else: :http
    port = uri.port || if(ws_scheme == :wss, do: 443, else: 80)
    path = (uri.path || "/") <> if(uri.query, do: "?#{uri.query}", else: "")

    with {:ok, conn} <- Mint.HTTP.connect(http_scheme, uri.host, port, protocols: [:http1]),
         {:ok, conn, ref} <- Mint.WebSocket.upgrade(ws_scheme, conn, path, []) do
      state = %__MODULE__{conn: conn, ref: ref, url: url}
      await_upgrade(state)
    else
      {:error, reason} ->
        {:stop, reason}

      {:error, _conn, reason} ->
        {:stop, reason}
    end
  end

  defp await_upgrade(%{websocket: ws} = state) when not is_nil(ws), do: {:ok, state}

  defp await_upgrade(state) do
    receive do
      message ->
        case Mint.WebSocket.stream(state.conn, message) do
          {:ok, conn, responses} ->
            state = %{state | conn: conn}
            state = handle_responses(state, responses)
            await_upgrade(state)

          {:error, _conn, reason, _responses} ->
            {:stop, reason}

          :unknown ->
            await_upgrade(state)
        end
    after
      5_000 ->
        {:stop, :upgrade_timeout}
    end
  end

  @impl true
  def handle_call({:rpc_call, method, params}, from, state) do
    {id, state} = next_id(state)

    payload =
      Jason.encode!(%{"jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params})

    case send_frame(state, {:text, payload}) do
      {:ok, state} ->
        state = put_in(state.caller_map[id], {:call, from})
        {:noreply, state}

      {:error, state, reason} ->
        {:reply, {:error, %Error{message: "send failed: #{inspect(reason)}"}}, state}
    end
  end

  def handle_call({:subscribe, event, params, subscriber}, from, state) do
    {id, state} = next_id(state)

    payload =
      Jason.encode!(%{
        "jsonrpc" => "2.0",
        "id" => id,
        "method" => "eth_subscribe",
        "params" => [event | params]
      })

    case send_frame(state, {:text, payload}) do
      {:ok, state} ->
        state = put_in(state.caller_map[id], {:subscribe, from, subscriber})
        {:noreply, state}

      {:error, state, reason} ->
        {:reply, {:error, %Error{message: "send failed: #{inspect(reason)}"}}, state}
    end
  end

  def handle_call({:unsubscribe, sub_id}, from, state) do
    {id, state} = next_id(state)

    payload =
      Jason.encode!(%{
        "jsonrpc" => "2.0",
        "id" => id,
        "method" => "eth_unsubscribe",
        "params" => [sub_id]
      })

    case send_frame(state, {:text, payload}) do
      {:ok, state} ->
        state = put_in(state.caller_map[id], {:unsubscribe, from, sub_id})
        {:noreply, state}

      {:error, state, reason} ->
        {:reply, {:error, %Error{message: "send failed: #{inspect(reason)}"}}, state}
    end
  end

  @impl true
  def handle_info(message, state) do
    case Mint.WebSocket.stream(state.conn, message) do
      {:ok, conn, responses} ->
        state = %{state | conn: conn}
        state = handle_responses(state, responses)
        {:noreply, state}

      {:error, conn, reason, _responses} ->
        Logger.warning("ExecutionChain WebSocket error: #{inspect(reason)}")
        {:noreply, %{state | conn: conn}}

      :unknown ->
        {:noreply, state}
    end
  end

  # --- Internal ---

  defp handle_responses(state, responses) do
    Enum.reduce(responses, state, fn
      {:status, ref, status}, acc when ref == acc.ref ->
        %{acc | upgrade_status: status}

      {:headers, ref, headers}, acc when ref == acc.ref ->
        %{acc | upgrade_headers: (acc.upgrade_headers || []) ++ headers}

      {:done, ref}, acc when ref == acc.ref and is_nil(acc.websocket) ->
        # Upgrade complete — initialize the WebSocket
        case Mint.WebSocket.new(acc.conn, ref, acc.upgrade_status, acc.upgrade_headers) do
          {:ok, conn, websocket} ->
            %{acc | conn: conn, websocket: websocket, upgrade_status: nil, upgrade_headers: nil}

          {:error, conn, reason} ->
            Logger.warning("WebSocket upgrade failed: #{inspect(reason)}")
            %{acc | conn: conn}
        end

      {:data, ref, data}, acc when ref == acc.ref and not is_nil(acc.websocket) ->
        case Mint.WebSocket.decode(acc.websocket, data) do
          {:ok, websocket, frames} ->
            acc = %{acc | websocket: websocket}
            Enum.reduce(frames, acc, &handle_frame/2)

          {:error, websocket, reason} ->
            Logger.warning("WebSocket decode error: #{inspect(reason)}")
            %{acc | websocket: websocket}
        end

      _, acc ->
        acc
    end)
  end

  defp handle_frame({:text, text}, state) do
    case Jason.decode(text) do
      {:ok, %{"id" => id, "result" => result}} when is_map_key(state.caller_map, id) ->
        handle_rpc_result(state, id, {:ok, result})

      {:ok, %{"id" => id, "error" => %{"code" => code, "message" => msg}}}
      when is_map_key(state.caller_map, id) ->
        handle_rpc_result(state, id, {:error, %Error{code: code, message: msg}})

      {:ok,
       %{
         "method" => "eth_subscription",
         "params" => %{"subscription" => sub_id, "result" => data}
       }} ->
        case Map.get(state.sub_map, sub_id) do
          nil -> state
          pid -> send(pid, {:eth_subscription, sub_id, data}); state
        end

      {:ok, _other} ->
        state

      {:error, _} ->
        state
    end
  end

  defp handle_frame({:ping, data}, state) do
    case send_frame(state, {:pong, data}) do
      {:ok, state} -> state
      {:error, state, _} -> state
    end
  end

  defp handle_frame({:close, _code, _reason}, state) do
    Logger.info("ExecutionChain WebSocket closed by server")
    state
  end

  defp handle_frame(_frame, state), do: state

  defp handle_rpc_result(state, id, result) do
    {entry, caller_map} = Map.pop(state.caller_map, id)
    state = %{state | caller_map: caller_map}

    case entry do
      {:call, from} ->
        GenServer.reply(from, result)
        state

      {:subscribe, from, subscriber} ->
        case result do
          {:ok, sub_id} ->
            GenServer.reply(from, {:ok, sub_id})
            put_in(state.sub_map[sub_id], subscriber)

          error ->
            GenServer.reply(from, error)
            state
        end

      {:unsubscribe, from, sub_id} ->
        GenServer.reply(from, result)
        %{state | sub_map: Map.delete(state.sub_map, sub_id)}

      nil ->
        state
    end
  end

  defp send_frame(%{websocket: nil} = state, _frame) do
    {:error, state, :not_connected}
  end

  defp send_frame(state, frame) do
    case Mint.WebSocket.encode(state.websocket, frame) do
      {:ok, websocket, data} ->
        case Mint.WebSocket.stream_request_body(state.conn, state.ref, data) do
          {:ok, conn} ->
            {:ok, %{state | conn: conn, websocket: websocket}}

          {:error, conn, reason} ->
            {:error, %{state | conn: conn, websocket: websocket}, reason}
        end

      {:error, websocket, reason} ->
        {:error, %{state | websocket: websocket}, reason}
    end
  end

  defp next_id(state) do
    {state.next_id, %{state | next_id: state.next_id + 1}}
  end
end
