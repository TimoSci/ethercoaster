defmodule Ethercoaster.Service.Worker do
  use GenServer, restart: :temporary

  require Logger

  alias Ethercoaster.{Services, Validators}
  alias Ethercoaster.Validator.Cache
  alias Ethercoaster.BeaconChain.{Beacon, Client, Node, Rewards}

  @slots_per_epoch 32
  @max_log_entries 50

  # --- Client API ---

  def start_link(service_id) do
    GenServer.start_link(__MODULE__, service_id,
      name: {:via, Registry, {Ethercoaster.ServiceRegistry, service_id}}
    )
  end

  def pause(pid), do: GenServer.cast(pid, :pause)

  def get_state(pid) do
    GenServer.call(pid, :get_state, 2_000)
  catch
    :exit, _ -> %{status: :running, epochs_completed: 0, epochs_total: 0, log: ["Worker busy..."]}
  end

  # --- Server callbacks ---

  @impl true
  def init(service_id) do
    state = %{
      service_id: service_id,
      status: :initializing,
      validators: [],
      work_queue: [],
      epochs_completed: 0,
      epochs_total: 0,
      log: [],
      paused: false,
      genesis_time: nil,
      consensus_endpoint: nil,
      execution_endpoint: nil,
      categories: [],
      batch_size: default_batch_size(),
      last_batch_ms: nil,
      batch_times: [],
      batch_started_at: nil
    }

    {:ok, state, {:continue, :setup}}
  end

  @impl true
  def handle_continue(:setup, state) do
    service = Services.get_service!(state.service_id)
    Client.put_base_url(service.consensus_endpoint)

    case resolve_epoch_range(service) do
      {:ok, from_epoch, to_epoch} ->
        validators = resolve_service_validators(service)

        if validators == [] do
          skipped = length(service.validators)
          state = add_log(state, "No validators with a known index (#{skipped} skipped)")
          state = %{state | status: :error}
          broadcast_state(state, :status_change)
          {:stop, :normal, state}
        else
          skipped = length(service.validators) - length(validators)
          if skipped > 0, do: Logger.warning("Service #{state.service_id}: skipping #{skipped} validator(s) with no index")

        categories = Enum.map(service.categories, &String.to_existing_atom/1)
        genesis_time = get_genesis_time()

        work_queue = build_work_queue(validators, from_epoch, to_epoch, categories)
        total = length(Enum.to_list(from_epoch..to_epoch)) * length(validators) * length(categories)
        completed = total - length(work_queue)

        batch_size = service.batch_size || default_batch_size()

        state = %{state |
          status: :running,
          validators: validators,
          work_queue: work_queue,
          epochs_completed: completed,
          epochs_total: total,
          genesis_time: genesis_time,
          consensus_endpoint: service.consensus_endpoint,
          execution_endpoint: service.execution_endpoint,
          categories: categories,
          batch_size: batch_size
        }

        state = add_log(state, "Started — #{length(work_queue)} items to fetch")
        broadcast_state(state, :status_change)
        send(self(), :process_batch)
        {:noreply, state}
        end

      {:error, reason} ->
        state = add_log(state, "Failed to start: #{reason}")
        broadcast_state(state, :status_change)
        {:stop, :normal, state}
    end
  end

  @impl true
  def handle_cast(:pause, state) do
    state = %{state | paused: true}
    state = add_log(state, "Pause requested — finishing current batch")
    {:noreply, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    reply = %{
      service_id: state.service_id,
      status: state.status,
      epochs_completed: state.epochs_completed,
      epochs_total: state.epochs_total,
      log: Enum.reverse(state.log),
      last_batch_ms: state.last_batch_ms,
      avg_batch_ms: avg_batch_ms(state.batch_times),
      batch_started_at: state.batch_started_at
    }
    {:reply, reply, state}
  end

  @impl true
  def handle_info(:process_batch, %{paused: true} = state) do
    state = %{state | status: :paused}
    state = add_log(state, "Paused")
    broadcast_state(state, :status_change)
    {:stop, :normal, state}
  end

  def handle_info(:process_batch, %{work_queue: []} = state) do
    Services.update_service_status(state.service_id, "completed")
    state = %{state | status: :completed}
    state = add_log(state, "Completed")
    broadcast_state(state, :status_change)
    {:stop, :normal, state}
  end

  def handle_info(:process_batch, state) do
    batch_start = System.monotonic_time(:millisecond)
    now_utc = DateTime.utc_now() |> DateTime.to_unix(:millisecond)

    effective_size = effective_batch_size(state.work_queue, state.batch_size)
    {batch, rest} = Enum.split(state.work_queue, effective_size)
    state = %{state | work_queue: rest, batch_started_at: now_utc}

    broadcast_state(state, :batch_started)

    # Group batch items by {validator_id, category}
    groups = Enum.group_by(batch, fn {validator, _epoch, category} -> {validator.id, category} end)

    consensus_endpoint = state.consensus_endpoint

    tasks =
      Enum.map(groups, fn {{_vid, category}, items} ->
        validator = elem(hd(items), 0)
        epochs = Enum.map(items, &elem(&1, 1))

        Task.async(fn ->
          Client.put_base_url(consensus_endpoint)
          fetch_and_store(validator, epochs, category, state.genesis_time)
        end)
      end)

    results = Task.await_many(tasks, 120_000)

    batch_ms = System.monotonic_time(:millisecond) - batch_start
    batch_times = Enum.take([batch_ms | state.batch_times], 20)

    completed_count = length(batch)
    state = %{state |
      epochs_completed: state.epochs_completed + completed_count,
      last_batch_ms: batch_ms,
      batch_times: batch_times,
      batch_started_at: nil
    }

    succeeded = Enum.count(results, &(&1 == :ok))
    failed = length(results) - succeeded

    log_msg = "Batch: #{completed_count} items (#{succeeded} ok, #{failed} failed) — #{state.epochs_completed}/#{state.epochs_total} [#{format_ms(batch_ms)}]"
    state = add_log(state, log_msg)
    broadcast_state(state, :progress)

    send(self(), :process_batch)
    {:noreply, state}
  end

  # --- Private helpers ---

  defp resolve_epoch_range(service) do
    case service.query_mode do
      "last_n_epochs" ->
        case get_head_slot() do
          {:ok, head_slot} ->
            to_epoch = div(head_slot, @slots_per_epoch) - 1
            from_epoch = max(to_epoch - service.last_n_epochs + 1, 0)
            {:ok, from_epoch, to_epoch}

          {:error, reason} ->
            {:error, reason}
        end

      "epoch_range" ->
        {:ok, service.epoch_from, service.epoch_to}
    end
  end

  defp resolve_service_validators(service) do
    service.validators
    |> Enum.map(fn vr ->
      if is_nil(vr.index) or is_nil(vr.public_key) or vr.public_key == "" do
        Validators.resolve_from_beacon(vr)
      else
        vr
      end
    end)
    |> Enum.filter(fn vr -> is_integer(vr.index) end)
    |> Enum.map(fn vr ->
      %{id: vr.id, public_key: vr.public_key, index: vr.index}
    end)
  end

  defp build_work_queue(validators, from_epoch, to_epoch, categories) do
    all_epochs = Enum.to_list(from_epoch..to_epoch)

    # Sort categories so :block_proposal comes first
    sorted_categories = Enum.sort_by(categories, fn
      :block_proposal -> 0
      _ -> 1
    end)

    for validator <- validators,
        category <- sorted_categories,
        epoch <- uncached_epochs(validator.id, from_epoch, to_epoch, all_epochs, category) do
      {validator, epoch, category}
    end
  end

  defp uncached_epochs(validator_id, from_epoch, to_epoch, all_epochs, category) do
    cached = Cache.get_cached_epoch_set(validator_id, from_epoch, to_epoch, Atom.to_string(category))
    Enum.reject(all_epochs, &MapSet.member?(cached, &1))
  end

  defp fetch_and_store(validator, epochs, :attestation, genesis_time) do
    index_str = Integer.to_string(validator.index)

    try do
      data = fetch_attestation_rewards(epochs, index_str)
      Cache.store_and_mark(:attestation, validator.id, data, epochs, genesis_time)
      :ok
    rescue
      e ->
        Logger.error("Service worker attestation fetch failed: #{inspect(e)}")
        :error
    end
  end

  defp fetch_and_store(validator, epochs, :block_proposal, genesis_time) do
    try do
      {:ok, data} = Rewards.fetch_proposal_rewards(epochs, validator.index)
      Cache.store_and_mark(:block_proposal, validator.id, data, epochs, genesis_time)
      :ok
    rescue
      e ->
        Logger.error("Service worker block proposal fetch failed: #{inspect(e)}")
        :error
    end
  end

  defp fetch_and_store(_validator, _epochs, _category, _genesis_time) do
    # Future categories — no-op for now
    :ok
  end

  defp fetch_attestation_rewards(epochs, index_str) do
    max_concurrency =
      :ethercoaster
      |> Application.get_env(Ethercoaster.BeaconChain, [])
      |> Keyword.get(:max_concurrency, 16)

    base_url = Client.get_base_url()

    epochs
    |> Task.async_stream(
      fn epoch ->
        Client.put_base_url(base_url)

        case Beacon.get_attestation_rewards(Integer.to_string(epoch), [index_str]) do
          {:ok, %{"total_rewards" => [reward | _]}} ->
            {:ok,
             %{
               epoch: epoch,
               head: parse_int(reward["head"]),
               target: parse_int(reward["target"]),
               source: parse_int(reward["source"]),
               inactivity: parse_int(reward["inactivity"])
             }}

          {:error, _} ->
            :error
        end
      end,
      max_concurrency: max_concurrency,
      timeout: 30_000
    )
    |> Enum.flat_map(fn
      {:ok, {:ok, data}} -> [data]
      _ -> []
    end)
  end

  defp get_head_slot do
    case Node.get_syncing() do
      {:ok, %{"head_slot" => head_slot}} -> {:ok, parse_int(head_slot)}
      {:error, _} -> {:error, "Could not reach beacon node"}
    end
  end

  defp get_genesis_time do
    case Beacon.get_genesis() do
      {:ok, %{"genesis_time" => gt}} -> parse_int(gt)
      _ -> 1_606_824_023
    end
  end

  defp parse_int(val) when is_integer(val), do: val
  defp parse_int(val) when is_binary(val), do: String.to_integer(val)

  defp add_log(state, message) do
    timestamp = Calendar.strftime(DateTime.utc_now(), "%H:%M:%S")
    entry = "[#{timestamp}] #{message}"
    log = Enum.take([entry | state.log], @max_log_entries)
    %{state | log: log}
  end

  defp avg_batch_ms([]), do: nil
  defp avg_batch_ms(times), do: round(Enum.sum(times) / length(times))

  defp format_ms(ms) when ms < 1000, do: "#{ms}ms"
  defp format_ms(ms), do: "#{Float.round(ms / 1000, 1)}s"

  defp default_batch_size do
    Application.get_env(:ethercoaster, Ethercoaster.BeaconChain, [])
    |> Keyword.get(:batch_size, 50)
  end

  defp effective_batch_size([], base_size), do: base_size

  defp effective_batch_size([{_, _, front_category} | _], base_size) do
    overrides = Application.get_env(:ethercoaster, Ethercoaster.BeaconChain, [])
                |> Keyword.get(:batch_sizes, %{})

    Map.get(overrides, front_category, base_size)
  end

  defp state_snapshot(state) do
    %{
      service_id: state.service_id,
      status: state.status,
      epochs_completed: state.epochs_completed,
      epochs_total: state.epochs_total,
      log: Enum.reverse(state.log),
      last_batch_ms: state.last_batch_ms,
      avg_batch_ms: avg_batch_ms(state.batch_times),
      batch_started_at: state.batch_started_at
    }
  end

  defp broadcast_state(state, event) do
    Phoenix.PubSub.broadcast(
      Ethercoaster.PubSub,
      "service:#{state.service_id}",
      {event, state_snapshot(state)}
    )
  end
end
