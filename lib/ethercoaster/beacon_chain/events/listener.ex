defmodule Ethercoaster.BeaconChain.Events.Listener do
  @moduledoc """
  GenServer that maintains a long-lived SSE connection to the Beacon Chain
  event stream and broadcasts parsed events via `Ethercoaster.BeaconChain.Events`.

  ## Options

    * `:topics` — list of event topics to subscribe to
      (default: `["head", "block", "attestation", "finalized_checkpoint"]`)

  ## Usage

      # In your supervision tree (controlled by :events_enabled config):
      {Ethercoaster.BeaconChain.Events.Listener, topics: ["head", "block"]}
  """

  use GenServer

  require Logger

  alias Ethercoaster.BeaconChain.{Client, Events}

  @default_topics ["head", "block", "attestation", "finalized_checkpoint"]
  @initial_backoff 1_000
  @max_backoff 30_000

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    topics = Keyword.get(opts, :topics, @default_topics)

    state = %{
      topics: topics,
      req_ref: nil,
      buffer: "",
      current_event: nil,
      current_data: "",
      backoff: @initial_backoff
    }

    {:ok, state, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state) do
    {:noreply, connect(state)}
  end

  @impl true
  def handle_info({ref, {:data, chunk}}, %{req_ref: ref} = state) when is_reference(ref) do
    state = %{state | backoff: @initial_backoff}
    {:noreply, process_chunk(state, chunk)}
  end

  def handle_info({ref, :done}, %{req_ref: ref} = state) when is_reference(ref) do
    Logger.warning("BeaconChain SSE stream closed, reconnecting...")
    {:noreply, schedule_reconnect(state)}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{req_ref: ref} = state) do
    Logger.warning("BeaconChain SSE stream process down: #{inspect(reason)}, reconnecting...")
    {:noreply, schedule_reconnect(state)}
  end

  def handle_info(:reconnect, state) do
    {:noreply, connect(state)}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private

  defp connect(state) do
    topics_param = Enum.join(state.topics, ",")
    req = Client.new()

    case Req.get(req, url: "/eth/v1/events", params: [topics: topics_param], into: :self) do
      {:ok, %Req.Response{status: 200, body: ref}} when is_reference(ref) ->
        Logger.info("BeaconChain SSE connected, topics: #{topics_param}")
        %{state | req_ref: ref, buffer: "", current_event: nil, current_data: ""}

      {:ok, %Req.Response{status: status}} ->
        Logger.error("BeaconChain SSE connection failed with status #{status}")
        schedule_reconnect(state)

      {:error, reason} ->
        Logger.error("BeaconChain SSE connection error: #{inspect(reason)}")
        schedule_reconnect(state)
    end
  end

  defp schedule_reconnect(state) do
    Process.send_after(self(), :reconnect, state.backoff)
    next_backoff = min(state.backoff * 2, @max_backoff)
    %{state | req_ref: nil, backoff: next_backoff, buffer: "", current_event: nil, current_data: ""}
  end

  defp process_chunk(state, chunk) do
    buffer = state.buffer <> chunk
    {lines, remaining} = split_lines(buffer)

    state = %{state | buffer: remaining}
    Enum.reduce(lines, state, &process_line/2)
  end

  defp split_lines(buffer) do
    case String.split(buffer, "\n") do
      [single] -> {[], single}
      parts -> {Enum.slice(parts, 0..-2//1), List.last(parts)}
    end
  end

  defp process_line("event: " <> event_type, state) do
    %{state | current_event: String.trim(event_type)}
  end

  defp process_line("data: " <> data, state) do
    accumulated = if state.current_data == "", do: data, else: state.current_data <> "\n" <> data
    %{state | current_data: accumulated}
  end

  defp process_line("", %{current_event: event, current_data: data} = state)
       when is_binary(event) and data != "" do
    dispatch_event(event, data)
    %{state | current_event: nil, current_data: ""}
  end

  defp process_line(_line, state), do: state

  defp dispatch_event(topic, raw_data) do
    case Jason.decode(raw_data) do
      {:ok, data} ->
        Events.broadcast(topic, data)

      {:error, _reason} ->
        Events.broadcast(topic, raw_data)
    end
  end
end
