defmodule Ethercoaster.Service.Worker do
  use GenServer, restart: :temporary

  require Logger

  alias Ethercoaster.Services
  alias Ethercoaster.Validator.Cache
  alias Ethercoaster.BeaconChain.{Beacon, Node}

  @batch_size 50
  @slots_per_epoch 32
  @max_log_entries 50

  # --- Client API ---

  def start_link(service_id) do
    GenServer.start_link(__MODULE__, service_id,
      name: {:via, Registry, {Ethercoaster.ServiceRegistry, service_id}}
    )
  end

  def pause(pid), do: GenServer.cast(pid, :pause)

  def get_state(pid), do: GenServer.call(pid, :get_state)

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
      endpoint: nil,
      categories: []
    }

    {:ok, state, {:continue, :setup}}
  end

  @impl true
  def handle_continue(:setup, state) do
    service = Services.get_service!(state.service_id)

    case resolve_epoch_range(service) do
      {:ok, from_epoch, to_epoch} ->
        validators = resolve_service_validators(service)
        categories = Enum.map(service.categories, &String.to_existing_atom/1)
        genesis_time = get_genesis_time()

        work_queue = build_work_queue(validators, from_epoch, to_epoch, categories)
        total = length(Enum.to_list(from_epoch..to_epoch)) * length(validators) * length(categories)
        completed = total - length(work_queue)

        state = %{state |
          status: :running,
          validators: validators,
          work_queue: work_queue,
          epochs_completed: completed,
          epochs_total: total,
          genesis_time: genesis_time,
          endpoint: service.endpoint,
          categories: categories
        }

        state = add_log(state, "Started — #{length(work_queue)} items to fetch")
        broadcast(state, :status_change, :running)
        send(self(), :process_batch)
        {:noreply, state}

      {:error, reason} ->
        state = add_log(state, "Failed to start: #{reason}")
        broadcast(state, :status_change, :error)
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
      log: Enum.reverse(state.log)
    }
    {:reply, reply, state}
  end

  @impl true
  def handle_info(:process_batch, %{paused: true} = state) do
    state = %{state | status: :paused}
    state = add_log(state, "Paused")
    broadcast(state, :status_change, :paused)
    {:stop, :normal, state}
  end

  def handle_info(:process_batch, %{work_queue: []} = state) do
    Services.update_service_status(state.service_id, "completed")
    state = %{state | status: :completed}
    state = add_log(state, "Completed")
    broadcast(state, :status_change, :completed)
    {:stop, :normal, state}
  end

  def handle_info(:process_batch, state) do
    {batch, rest} = Enum.split(state.work_queue, @batch_size)
    state = %{state | work_queue: rest}

    # Group batch items by {validator_id, category}
    groups = Enum.group_by(batch, fn {validator, _epoch, category} -> {validator.id, category} end)

    tasks =
      Enum.map(groups, fn {{_vid, category}, items} ->
        validator = elem(hd(items), 0)
        epochs = Enum.map(items, &elem(&1, 1))

        Task.async(fn ->
          fetch_and_store(validator, epochs, category, state.genesis_time)
        end)
      end)

    results = Task.await_many(tasks, 120_000)

    completed_count = length(batch)
    state = %{state | epochs_completed: state.epochs_completed + completed_count}

    succeeded = Enum.count(results, &(&1 == :ok))
    failed = length(results) - succeeded

    log_msg = "Batch: #{completed_count} items (#{succeeded} ok, #{failed} failed) — #{state.epochs_completed}/#{state.epochs_total}"
    state = add_log(state, log_msg)
    broadcast(state, :progress, %{
      epochs_completed: state.epochs_completed,
      epochs_total: state.epochs_total,
      log_entry: log_msg
    })

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
    Enum.map(service.validators, fn vr ->
      %{id: vr.id, public_key: vr.public_key, index: vr.index}
    end)
  end

  defp build_work_queue(validators, from_epoch, to_epoch, categories) do
    all_epochs = Enum.to_list(from_epoch..to_epoch)

    for validator <- validators,
        category <- categories,
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

  defp fetch_and_store(_validator, _epochs, _category, _genesis_time) do
    # Future categories — no-op for now
    :ok
  end

  defp fetch_attestation_rewards(epochs, index_str) do
    max_concurrency =
      :ethercoaster
      |> Application.get_env(Ethercoaster.BeaconChain, [])
      |> Keyword.get(:max_concurrency, 16)

    epochs
    |> Task.async_stream(
      fn epoch ->
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

  defp broadcast(state, event, payload) do
    Phoenix.PubSub.broadcast(
      Ethercoaster.PubSub,
      "service:#{state.service_id}",
      {event, payload}
    )
  end
end
