# Services Feature Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a "Services" feature with a LiveView UI for creating persistent background query jobs that fetch validator attestation rewards in batches, with play/pause control and real-time progress.

**Architecture:** DB-persisted services with a DynamicSupervisor managing per-service GenServer workers. LiveView subscribes to PubSub for real-time progress. Workers fetch attestation rewards in 50-epoch batches, using the existing Cache module to avoid re-fetching.

**Tech Stack:** Elixir, Phoenix LiveView, Ecto, GenServer, DynamicSupervisor, Registry, PubSub, daisyUI/Tailwind

---

### Task 1: Migration — services table and join table

**Files:**
- Create: `priv/repo/migrations/TIMESTAMP_create_services.exs`

**Step 1: Create the migration**

```elixir
defmodule Ethercoaster.Repo.Migrations.CreateServices do
  use Ecto.Migration

  def change do
    create table(:services) do
      add :name, :string
      add :categories, {:array, :string}, null: false, default: ["attestation"]
      add :query_mode, :string, null: false
      add :last_n_epochs, :integer
      add :epoch_from, :integer
      add :epoch_to, :integer
      add :endpoint, :string
      add :status, :string, null: false, default: "stopped"

      timestamps(type: :utc_datetime)
    end

    create table(:services_validators, primary_key: false) do
      add :service_id, references(:services, on_delete: :delete_all), null: false
      add :validator_id, references(:validators, on_delete: :delete_all), null: false
    end

    create unique_index(:services_validators, [:service_id, :validator_id])
  end
end
```

**Step 2: Run the migration**

Run: `mix ecto.migrate`
Expected: Migration runs successfully

**Step 3: Commit**

```bash
git add priv/repo/migrations/*_create_services.exs
git commit -m "Add services and services_validators migration"
```

---

### Task 2: Service schema and context

**Files:**
- Create: `lib/ethercoaster/service.ex` (schema)
- Create: `lib/ethercoaster/service_validator.ex` (join schema)
- Create: `lib/ethercoaster/services.ex` (context module)

**Step 1: Create the Service schema**

```elixir
defmodule Ethercoaster.Service do
  use Ecto.Schema
  import Ecto.Changeset

  schema "services" do
    field :name, :string
    field :categories, {:array, :string}, default: ["attestation"]
    field :query_mode, :string
    field :last_n_epochs, :integer
    field :epoch_from, :integer
    field :epoch_to, :integer
    field :endpoint, :string
    field :status, :string, default: "stopped"

    many_to_many :validators, Ethercoaster.ValidatorRecord,
      join_through: "services_validators",
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  def changeset(service, attrs) do
    service
    |> cast(attrs, [:name, :categories, :query_mode, :last_n_epochs, :epoch_from, :epoch_to, :endpoint, :status])
    |> validate_required([:query_mode, :categories])
    |> validate_inclusion(:query_mode, ["last_n_epochs", "epoch_range"])
    |> validate_inclusion(:status, ["stopped", "completed"])
    |> validate_query_mode_fields()
  end

  defp validate_query_mode_fields(changeset) do
    case get_field(changeset, :query_mode) do
      "last_n_epochs" ->
        validate_required(changeset, [:last_n_epochs])

      "epoch_range" ->
        changeset
        |> validate_required([:epoch_from, :epoch_to])

      _ ->
        changeset
    end
  end
end
```

**Step 2: Create the ServiceValidator join schema**

```elixir
defmodule Ethercoaster.ServiceValidator do
  use Ecto.Schema

  @primary_key false
  schema "services_validators" do
    belongs_to :service, Ethercoaster.Service
    belongs_to :validator, Ethercoaster.ValidatorRecord
  end
end
```

**Step 3: Create the Services context**

```elixir
defmodule Ethercoaster.Services do
  import Ecto.Query

  alias Ethercoaster.Repo
  alias Ethercoaster.Service
  alias Ethercoaster.ValidatorRecord
  alias Ethercoaster.Validator.Cache

  def list_services do
    Service
    |> order_by(desc: :inserted_at)
    |> preload(:validators)
    |> Repo.all()
  end

  def get_service!(id) do
    Service
    |> preload(:validators)
    |> Repo.get!(id)
  end

  def create_service(attrs, validator_inputs) do
    Repo.transaction(fn ->
      changeset = Service.changeset(%Service{}, attrs)

      case Repo.insert(changeset) do
        {:ok, service} ->
          validator_records = resolve_validators(validator_inputs)
          service = service |> Repo.preload(:validators) |> Ecto.Changeset.change() |> Ecto.Changeset.put_assoc(:validators, validator_records) |> Repo.update!()
          service

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  def update_service_status(service_id, status) do
    Service
    |> Repo.get!(service_id)
    |> Ecto.Changeset.change(status: status)
    |> Repo.update!()
  end

  def delete_service(id) do
    Service
    |> Repo.get!(id)
    |> Repo.delete()
  end

  defp resolve_validators(inputs) do
    Enum.map(inputs, fn input ->
      input = String.trim(input)

      cond do
        String.match?(input, ~r/\A0x[0-9a-fA-F]{96}\z/) ->
          case Repo.get_by(ValidatorRecord, public_key: input) do
            %ValidatorRecord{} = record -> record
            nil ->
              # Will be fully resolved when worker starts and calls the beacon API
              Repo.insert!(%ValidatorRecord{public_key: input, index: 0},
                on_conflict: :nothing, conflict_target: :public_key)
              Repo.get_by!(ValidatorRecord, public_key: input)
          end

        String.match?(input, ~r/\A\d+\z/) ->
          index = String.to_integer(input)
          case Repo.get_by(ValidatorRecord, index: index) do
            %ValidatorRecord{} = record -> record
            nil ->
              Repo.insert!(%ValidatorRecord{public_key: "unresolved:#{index}", index: index},
                on_conflict: :nothing, conflict_target: :index)
              Repo.get_by!(ValidatorRecord, index: index)
          end

        true ->
          raise "Invalid validator input: #{input}"
      end
    end)
    |> Enum.uniq_by(& &1.id)
  end
end
```

**Step 4: Run tests to verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Compiles cleanly

**Step 5: Commit**

```bash
git add lib/ethercoaster/service.ex lib/ethercoaster/service_validator.ex lib/ethercoaster/services.ex
git commit -m "Add Service schema, join schema, and Services context"
```

---

### Task 3: ServiceRegistry and ServiceManager (DynamicSupervisor)

**Files:**
- Create: `lib/ethercoaster/service/manager.ex`
- Modify: `lib/ethercoaster/application.ex`

**Step 1: Create the ServiceManager**

```elixir
defmodule Ethercoaster.Service.Manager do
  use DynamicSupervisor

  alias Ethercoaster.Service.Worker

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_service(service_id) do
    case Registry.lookup(Ethercoaster.ServiceRegistry, service_id) do
      [{_pid, _}] ->
        {:error, :already_running}

      [] ->
        DynamicSupervisor.start_child(__MODULE__, {Worker, service_id})
    end
  end

  def stop_service(service_id) do
    case Registry.lookup(Ethercoaster.ServiceRegistry, service_id) do
      [{pid, _}] ->
        Worker.pause(pid)
        :ok

      [] ->
        {:error, :not_running}
    end
  end

  def get_worker_pid(service_id) do
    case Registry.lookup(Ethercoaster.ServiceRegistry, service_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> :error
    end
  end

  def get_worker_state(service_id) do
    case get_worker_pid(service_id) do
      {:ok, pid} -> Worker.get_state(pid)
      :error -> nil
    end
  end
end
```

**Step 2: Add Registry and Manager to the supervision tree**

Modify `lib/ethercoaster/application.ex` — add these two children before the Endpoint:

```elixir
{Registry, keys: :unique, name: Ethercoaster.ServiceRegistry},
{Ethercoaster.Service.Manager, []},
```

The children list becomes (showing the relevant section):
```elixir
{Phoenix.PubSub, name: Ethercoaster.PubSub},
{Registry, keys: :unique, name: Ethercoaster.ServiceRegistry},
{Ethercoaster.Service.Manager, []},
```

**Step 3: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Compiles (Worker module doesn't exist yet, that's fine — it's only referenced at runtime)

**Step 4: Commit**

```bash
git add lib/ethercoaster/service/manager.ex lib/ethercoaster/application.ex
git commit -m "Add ServiceRegistry and ServiceManager DynamicSupervisor"
```

---

### Task 4: Service Worker GenServer

**Files:**
- Create: `lib/ethercoaster/service/worker.ex`

**Step 1: Create the Worker GenServer**

```elixir
defmodule Ethercoaster.Service.Worker do
  use GenServer, restart: :temporary

  require Logger

  alias Ethercoaster.Services
  alias Ethercoaster.Validator.Cache
  alias Ethercoaster.BeaconChain.{Beacon, Node}

  @batch_size 50
  @slots_per_epoch 32
  @seconds_per_slot 12
  @seconds_per_epoch @slots_per_epoch * @seconds_per_slot
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
      paused: false
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
        genesis_time = get_genesis_time(service.endpoint)

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

        add_log(state, "Started — #{length(work_queue)} items to fetch")
        broadcast(state, :status_change, :running)
        send(self(), :process_batch)
        {:noreply, state}

      {:error, reason} ->
        add_log(state, "Failed to start: #{reason}")
        broadcast(state, :status_change, :error)
        {:stop, :normal, state}
    end
  end

  @impl true
  def handle_cast(:pause, state) do
    state = %{state | paused: true}
    add_log(state, "Pause requested — finishing current batch")
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
    add_log(state, "Paused")
    broadcast(state, :status_change, :paused)
    {:stop, :normal, state}
  end

  def handle_info(:process_batch, %{work_queue: []} = state) do
    Services.update_service_status(state.service_id, "completed")
    state = %{state | status: :completed}
    add_log(state, "Completed")
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
          fetch_and_store(validator, epochs, category, state.genesis_time, state.endpoint)
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
        case get_head_slot(service.endpoint) do
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

  defp fetch_and_store(validator, epochs, :attestation, genesis_time, endpoint) do
    index_str = Integer.to_string(validator.index)

    try do
      data = fetch_attestation_rewards(epochs, index_str, endpoint)
      Cache.store_and_mark(:attestation, validator.id, data, epochs, genesis_time)
      :ok
    rescue
      e ->
        Logger.error("Service worker attestation fetch failed: #{inspect(e)}")
        :error
    end
  end

  defp fetch_and_store(_validator, _epochs, _category, _genesis_time, _endpoint) do
    # Future categories — no-op for now
    :ok
  end

  defp fetch_attestation_rewards(epochs, index_str, _endpoint) do
    # Reuses the same beacon API calls as Ethercoaster.Validator
    max_concurrency = Application.get_env(:ethercoaster, Ethercoaster.BeaconChain, [])
                      |> Keyword.get(:max_concurrency, 16)

    epochs
    |> Task.async_stream(
      fn epoch ->
        case Beacon.get_attestation_rewards(Integer.to_string(epoch), [index_str]) do
          {:ok, %{"total_rewards" => [reward | _]}} ->
            {:ok, %{
              epoch: epoch,
              head: parse_int(reward["head"]),
              target: parse_int(reward["target"]),
              source: parse_int(reward["source"]),
              inactivity: parse_int(reward["inactivity"])
            }}
          {:error, _} -> :error
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

  defp get_head_slot(_endpoint) do
    case Node.get_syncing() do
      {:ok, %{"head_slot" => head_slot}} -> {:ok, parse_int(head_slot)}
      {:error, _} -> {:error, "Could not reach beacon node"}
    end
  end

  defp get_genesis_time(_endpoint) do
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
```

**Step 2: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Compiles cleanly

**Step 3: Commit**

```bash
git add lib/ethercoaster/service/worker.ex
git commit -m "Add Service Worker GenServer with batch processing"
```

---

### Task 5: LiveView — route and basic mount

**Files:**
- Create: `lib/ethercoaster_web/live/service_live.ex`
- Modify: `lib/ethercoaster_web/router.ex`

**Step 1: Add the LiveView route**

In `lib/ethercoaster_web/router.ex`, inside the `scope "/", EthercoasterWeb do` block, add:

```elixir
live "/services", ServiceLive
```

**Step 2: Create the initial LiveView module**

```elixir
defmodule EthercoasterWeb.ServiceLive do
  use EthercoasterWeb, :live_view

  alias Ethercoaster.Services
  alias Ethercoaster.Service.Manager

  @impl true
  def mount(_params, _session, socket) do
    services = Services.list_services()

    # Subscribe to PubSub for all services
    if connected?(socket) do
      for service <- services do
        Phoenix.PubSub.subscribe(Ethercoaster.PubSub, "service:#{service.id}")
      end
    end

    # Build runtime state map from Registry
    worker_states =
      Map.new(services, fn service ->
        case Manager.get_worker_state(service.id) do
          nil -> {service.id, %{status: String.to_atom(service.status), epochs_completed: 0, epochs_total: 0, log: []}}
          ws -> {service.id, ws}
        end
      end)

    socket =
      socket
      |> assign(:services, services)
      |> assign(:worker_states, worker_states)
      |> assign(:form_validators, [""])
      |> assign(:form_error, nil)

    {:ok, socket}
  end

  # --- PubSub handlers ---

  @impl true
  def handle_info({:status_change, status}, socket) do
    # We need the service_id from the topic — use a helper
    {:noreply, socket}
  end

  def handle_info({:progress, %{} = payload}, socket) do
    {:noreply, socket}
  end

  # These will be fleshed out in Task 7 (event handlers)

  # --- Template ---

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Services
      <:subtitle>Create and manage background validator reward queries.</:subtitle>
    </.header>

    <div class="mt-6 space-y-6">
      <%!-- Create Service form --%>
      <div class="card bg-base-200 p-6">
        <h3 class="text-lg font-semibold mb-4">Create Service</h3>
        <.live_component module={EthercoasterWeb.ServiceLive.FormComponent} id="service-form" validators={@form_validators} form_error={@form_error} />
      </div>

      <%!-- Service cards stack --%>
      <div class="space-y-4">
        <div :for={service <- @services} id={"service-#{service.id}"}>
          <.live_component
            module={EthercoasterWeb.ServiceLive.CardComponent}
            id={"card-#{service.id}"}
            service={service}
            worker_state={Map.get(@worker_states, service.id)}
          />
        </div>
      </div>
    </div>
    """
  end
end
```

**Step 3: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Will warn about missing FormComponent and CardComponent — that's expected, we create them next.

**Step 4: Commit**

```bash
git add lib/ethercoaster_web/live/service_live.ex lib/ethercoaster_web/router.ex
git commit -m "Add ServiceLive LiveView with route and basic mount"
```

---

### Task 6: LiveView — Form component

**Files:**
- Create: `lib/ethercoaster_web/live/service_live/form_component.ex`

**Step 1: Create the form LiveComponent**

```elixir
defmodule EthercoasterWeb.ServiceLive.FormComponent do
  use EthercoasterWeb, :live_component

  @impl true
  def mount(socket) do
    socket =
      socket
      |> assign(:validators, [""])
      |> assign(:name, "")
      |> assign(:query_mode, "last_n_epochs")
      |> assign(:last_n_epochs, "")
      |> assign(:epoch_from, "")
      |> assign(:epoch_to, "")
      |> assign(:date_from, "")
      |> assign(:date_to, "")
      |> assign(:endpoint, "")
      |> assign(:categories, ["attestation"])
      |> assign(:upload_error, nil)
      |> allow_upload(:validator_file, accept: ~w(.csv .json), max_entries: 1)

    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, :form_error, assigns[:form_error])}
  end

  @impl true
  def handle_event("add_validator", _, socket) do
    validators = socket.assigns.validators ++ [""]
    {:noreply, assign(socket, :validators, validators)}
  end

  def handle_event("remove_validator", %{"index" => index}, socket) do
    index = String.to_integer(index)
    validators = List.delete_at(socket.assigns.validators, index)
    validators = if validators == [], do: [""], else: validators
    {:noreply, assign(socket, :validators, validators)}
  end

  def handle_event("update_validator", %{"index" => index, "value" => value}, socket) do
    index = String.to_integer(index)
    validators = List.replace_at(socket.assigns.validators, index, value)
    {:noreply, assign(socket, :validators, validators)}
  end

  def handle_event("update_field", %{"field" => field, "value" => value}, socket) do
    {:noreply, assign(socket, String.to_existing_atom(field), value)}
  end

  def handle_event("save", _params, socket) do
    send(self(), {:save_service, build_service_params(socket)})
    {:noreply, socket}
  end

  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("upload_validators", _params, socket) do
    uploaded =
      consume_uploaded_entries(socket, :validator_file, fn %{path: path}, entry ->
        content = File.read!(path)
        parse_validator_file(content, entry.client_name)
      end)

    case uploaded do
      [{:ok, parsed}] ->
        existing = Enum.reject(socket.assigns.validators, &(&1 == ""))
        validators = (existing ++ parsed) |> Enum.uniq()
        validators = if validators == [], do: [""], else: validators
        {:noreply, assign(socket, validators: validators, upload_error: nil)}

      [{:error, reason}] ->
        {:noreply, assign(socket, :upload_error, reason)}

      _ ->
        {:noreply, socket}
    end
  end

  defp parse_validator_file(content, filename) do
    cond do
      String.ends_with?(filename, ".json") ->
        case Jason.decode(content) do
          {:ok, list} when is_list(list) ->
            {:ok, Enum.map(list, &to_string/1)}
          {:ok, %{"validators" => list}} when is_list(list) ->
            {:ok, Enum.map(list, &to_string/1)}
          _ ->
            {:error, "JSON must be an array of validators or {\"validators\": [...]}"}
        end

      String.ends_with?(filename, ".csv") ->
        lines =
          content
          |> String.split(["\n", "\r\n"])
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
        {:ok, lines}

      true ->
        {:error, "Unsupported file type"}
    end
  end

  defp build_service_params(socket) do
    a = socket.assigns
    validators = Enum.reject(a.validators, &(&1 == ""))

    %{
      attrs: %{
        name: a.name,
        query_mode: a.query_mode,
        last_n_epochs: parse_int_or_nil(a.last_n_epochs),
        epoch_from: parse_int_or_nil(a.epoch_from),
        epoch_to: parse_int_or_nil(a.epoch_to),
        endpoint: if(a.endpoint == "", do: nil, else: a.endpoint),
        categories: a.categories
      },
      validators: validators
    }
  end

  defp parse_int_or_nil(""), do: nil
  defp parse_int_or_nil(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> n
      _ -> nil
    end
  end
  defp parse_int_or_nil(n) when is_integer(n), do: n
  defp parse_int_or_nil(_), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <form phx-submit="save" phx-target={@myself} class="space-y-4">
        <%!-- Name --%>
        <div>
          <label class="label">Name (optional)</label>
          <input
            type="text"
            value={@name}
            phx-blur="update_field"
            phx-value-field="name"
            phx-target={@myself}
            class="input input-bordered w-full"
            placeholder="My validator service"
          />
        </div>

        <%!-- Validators dynamic list --%>
        <div>
          <label class="label">Validators (public key or index)</label>
          <div class="space-y-2">
            <div :for={{val, idx} <- Enum.with_index(@validators)} class="flex gap-2">
              <input
                type="text"
                value={val}
                phx-blur="update_validator"
                phx-value-index={idx}
                phx-target={@myself}
                class="input input-bordered flex-1"
                placeholder="0x... or validator index"
              />
              <button
                type="button"
                phx-click="remove_validator"
                phx-value-index={idx}
                phx-target={@myself}
                class="btn btn-ghost btn-sm"
              >
                <.icon name="hero-x-mark" class="size-4" />
              </button>
            </div>
          </div>
          <div class="flex gap-2 mt-2">
            <button type="button" phx-click="add_validator" phx-target={@myself} class="btn btn-soft btn-sm">
              <.icon name="hero-plus" class="size-4" /> Add Validator
            </button>
            <form phx-change="validate_upload" phx-submit="upload_validators" phx-target={@myself} class="inline-flex gap-2">
              <.live_file_input upload={@uploads.validator_file} class="file-input file-input-bordered file-input-sm" />
              <button type="submit" class="btn btn-soft btn-sm">Upload</button>
            </form>
          </div>
          <p :if={@upload_error} class="text-error text-sm mt-1">{@upload_error}</p>
        </div>

        <%!-- Categories --%>
        <div>
          <label class="label">Transaction Categories</label>
          <div class="flex flex-wrap gap-4">
            <label class="label cursor-pointer gap-2">
              <input type="checkbox" checked disabled class="checkbox checkbox-primary" />
              <span>Attestation</span>
            </label>
            <label class="label cursor-pointer gap-2 opacity-50">
              <input type="checkbox" disabled class="checkbox" />
              <span>Sync Committee <span class="badge badge-sm">coming soon</span></span>
            </label>
            <label class="label cursor-pointer gap-2 opacity-50">
              <input type="checkbox" disabled class="checkbox" />
              <span>Block Proposal <span class="badge badge-sm">coming soon</span></span>
            </label>
          </div>
        </div>

        <%!-- Query mode fields --%>
        <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div>
            <label class="label">Last N Epochs</label>
            <input
              type="number"
              value={@last_n_epochs}
              phx-blur="update_field"
              phx-value-field="last_n_epochs"
              phx-target={@myself}
              class="input input-bordered w-full"
              min="1"
              placeholder="100"
            />
          </div>
          <div>
            <label class="label">Epoch From</label>
            <input
              type="number"
              value={@epoch_from}
              phx-blur="update_field"
              phx-value-field="epoch_from"
              phx-target={@myself}
              class="input input-bordered w-full"
              min="0"
              placeholder="0"
            />
          </div>
          <div>
            <label class="label">Epoch To</label>
            <input
              type="number"
              value={@epoch_to}
              phx-blur="update_field"
              phx-value-field="epoch_to"
              phx-target={@myself}
              class="input input-bordered w-full"
              min="0"
              placeholder="99"
            />
          </div>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <label class="label">Date From</label>
            <input
              type="date"
              value={@date_from}
              phx-blur="update_field"
              phx-value-field="date_from"
              phx-target={@myself}
              class="input input-bordered w-full"
            />
          </div>
          <div>
            <label class="label">Date To</label>
            <input
              type="date"
              value={@date_to}
              phx-blur="update_field"
              phx-value-field="date_to"
              phx-target={@myself}
              class="input input-bordered w-full"
            />
          </div>
        </div>

        <%!-- Endpoint --%>
        <div>
          <label class="label">Endpoint (optional)</label>
          <input
            type="text"
            value={@endpoint}
            phx-blur="update_field"
            phx-value-field="endpoint"
            phx-target={@myself}
            class="input input-bordered w-full"
            placeholder="http://localhost:5052"
          />
        </div>

        <%!-- Error display --%>
        <div :if={@form_error} class="alert alert-error">
          <.icon name="hero-exclamation-circle" class="size-5" />
          <span>{@form_error}</span>
        </div>

        <%!-- Submit --%>
        <button type="submit" class="btn btn-primary">
          <.icon name="hero-bookmark" class="size-5" /> Save Service
        </button>
      </form>
    </div>
    """
  end
end
```

**Step 2: Verify compilation**

Run: `mix compile --warnings-as-errors`

**Step 3: Commit**

```bash
git add lib/ethercoaster_web/live/service_live/form_component.ex
git commit -m "Add ServiceLive form component with dynamic validators and file upload"
```

---

### Task 7: LiveView — Card component

**Files:**
- Create: `lib/ethercoaster_web/live/service_live/card_component.ex`

**Step 1: Create the card LiveComponent**

```elixir
defmodule EthercoasterWeb.ServiceLive.CardComponent do
  use EthercoasterWeb, :live_component

  @impl true
  def render(assigns) do
    status = if assigns.worker_state, do: assigns.worker_state.status, else: :stopped
    epochs_completed = if assigns.worker_state, do: assigns.worker_state.epochs_completed, else: 0
    epochs_total = if assigns.worker_state, do: assigns.worker_state.epochs_total, else: 0
    log = if assigns.worker_state, do: assigns.worker_state.log, else: []
    progress_pct = if epochs_total > 0, do: Float.round(epochs_completed / epochs_total * 100, 1), else: 0

    assigns =
      assigns
      |> assign(:status, status)
      |> assign(:epochs_completed, epochs_completed)
      |> assign(:epochs_total, epochs_total)
      |> assign(:log, log)
      |> assign(:progress_pct, progress_pct)

    ~H"""
    <div class="card bg-base-200 p-4">
      <div class="flex items-center justify-between mb-2">
        <div class="flex items-center gap-3">
          <h4 class="font-semibold text-lg">
            {@service.name || "Service ##{@service.id}"}
          </h4>
          <.status_badge status={@status} />
        </div>
        <div class="flex gap-1">
          <button
            :if={@status in [:stopped, :paused]}
            phx-click="play_service"
            phx-value-id={@service.id}
            class="btn btn-success btn-sm"
          >
            <.icon name="hero-play" class="size-4" />
          </button>
          <button
            :if={@status == :running}
            phx-click="pause_service"
            phx-value-id={@service.id}
            class="btn btn-warning btn-sm"
          >
            <.icon name="hero-pause" class="size-4" />
          </button>
          <button
            phx-click="delete_service"
            phx-value-id={@service.id}
            data-confirm="Are you sure you want to delete this service?"
            class="btn btn-error btn-ghost btn-sm"
          >
            <.icon name="hero-trash" class="size-4" />
          </button>
        </div>
      </div>

      <%!-- Summary --%>
      <div class="text-sm opacity-70 mb-2">
        <span>{length(@service.validators)} validator(s)</span>
        <span class="mx-1">&middot;</span>
        <span :if={@service.query_mode == "last_n_epochs"}>Last {@service.last_n_epochs} epochs</span>
        <span :if={@service.query_mode == "epoch_range"}>Epochs {@service.epoch_from} – {@service.epoch_to}</span>
        <span class="mx-1">&middot;</span>
        <span :for={cat <- @service.categories} class="badge badge-sm mr-1">{cat}</span>
      </div>

      <%!-- Progress bar --%>
      <div class="mb-2">
        <div class="flex justify-between text-xs mb-1">
          <span>{@epochs_completed} / {@epochs_total}</span>
          <span>{@progress_pct}%</span>
        </div>
        <progress class="progress progress-primary w-full" value={@epochs_completed} max={@epochs_total}></progress>
      </div>

      <%!-- Log panel --%>
      <div
        :if={@log != []}
        class="bg-base-300 rounded p-2 max-h-32 overflow-y-auto text-xs font-mono"
        id={"log-#{@service.id}"}
        phx-hook="ScrollBottom"
      >
        <div :for={entry <- @log}>{entry}</div>
      </div>
    </div>
    """
  end

  defp status_badge(assigns) do
    {color, label} =
      case assigns.status do
        :running -> {"badge-success", "Running"}
        :paused -> {"badge-warning", "Paused"}
        :completed -> {"badge-info", "Completed"}
        :error -> {"badge-error", "Error"}
        _ -> {"badge-ghost", "Stopped"}
      end

    assigns = assign(assigns, :color, color) |> assign(:label, label)

    ~H"""
    <span class={"badge badge-sm #{@color}"}>{@label}</span>
    """
  end
end
```

**Step 2: Verify compilation**

Run: `mix compile --warnings-as-errors`

**Step 3: Commit**

```bash
git add lib/ethercoaster_web/live/service_live/card_component.ex
git commit -m "Add ServiceLive card component with progress and log display"
```

---

### Task 8: LiveView — event handlers (play, pause, delete, save, PubSub)

**Files:**
- Modify: `lib/ethercoaster_web/live/service_live.ex`

**Step 1: Replace the placeholder handle_info and add handle_event callbacks**

Add these to `ServiceLive`:

```elixir
# --- Form save ---

@impl true
def handle_info({:save_service, params}, socket) do
  case Services.create_service(params.attrs, params.validators) do
    {:ok, service} ->
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Ethercoaster.PubSub, "service:#{service.id}")
      end

      services = [service | socket.assigns.services]
      worker_states = Map.put(socket.assigns.worker_states, service.id, %{
        status: :stopped, epochs_completed: 0, epochs_total: 0, log: []
      })

      socket =
        socket
        |> assign(:services, services)
        |> assign(:worker_states, worker_states)
        |> assign(:form_error, nil)
        |> put_flash(:info, "Service created")

      {:noreply, socket}

    {:error, changeset} when is_struct(changeset, Ecto.Changeset) ->
      error = Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end) |> inspect()
      {:noreply, assign(socket, :form_error, "Validation failed: #{error}")}

    {:error, reason} ->
      {:noreply, assign(socket, :form_error, "Error: #{inspect(reason)}")}
  end
end

# --- PubSub handlers ---

@impl true
def handle_info({:status_change, status}, socket) do
  # Find which service this is for by checking all subscriptions
  # PubSub messages include the topic implicitly via the payload
  # We need to match by checking running workers
  services = socket.assigns.services
  worker_states =
    Map.new(services, fn service ->
      case Manager.get_worker_state(service.id) do
        nil ->
          existing = Map.get(socket.assigns.worker_states, service.id, %{status: :stopped, epochs_completed: 0, epochs_total: 0, log: []})
          # If status change is :completed or :paused, update the cached state
          {service.id, existing}
        ws ->
          {service.id, ws}
      end
    end)

  # Reload services from DB (status may have changed to "completed")
  services = Services.list_services()
  worker_states =
    Map.new(services, fn service ->
      case Manager.get_worker_state(service.id) do
        nil ->
          prev = Map.get(socket.assigns.worker_states, service.id, %{status: String.to_atom(service.status), epochs_completed: 0, epochs_total: 0, log: []})
          {service.id, prev}
        ws -> {service.id, ws}
      end
    end)

  {:noreply, assign(socket, services: services, worker_states: worker_states)}
end

def handle_info({:progress, %{} = payload}, socket) do
  # Find which service this progress is for
  worker_states =
    Enum.reduce(socket.assigns.services, socket.assigns.worker_states, fn service, acc ->
      case Manager.get_worker_state(service.id) do
        nil -> acc
        ws -> Map.put(acc, service.id, ws)
      end
    end)

  {:noreply, assign(socket, :worker_states, worker_states)}
end

# --- User actions ---

@impl true
def handle_event("play_service", %{"id" => id}, socket) do
  service_id = String.to_integer(id)

  case Manager.start_service(service_id) do
    {:ok, _pid} ->
      # Subscribe if not already
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Ethercoaster.PubSub, "service:#{service_id}")
      end

      worker_states = Map.put(socket.assigns.worker_states, service_id, %{
        status: :running, epochs_completed: 0, epochs_total: 0, log: ["Starting..."]
      })

      {:noreply, assign(socket, :worker_states, worker_states)}

    {:error, :already_running} ->
      {:noreply, put_flash(socket, :info, "Service is already running")}
  end
end

def handle_event("pause_service", %{"id" => id}, socket) do
  service_id = String.to_integer(id)
  Manager.stop_service(service_id)

  worker_states = update_in(
    socket.assigns.worker_states,
    [Access.key(service_id, %{})],
    &Map.put(&1, :status, :paused)
  )

  {:noreply, assign(socket, :worker_states, worker_states)}
end

def handle_event("delete_service", %{"id" => id}, socket) do
  service_id = String.to_integer(id)

  # Stop if running
  Manager.stop_service(service_id)
  Services.delete_service(service_id)

  services = Enum.reject(socket.assigns.services, &(&1.id == service_id))
  worker_states = Map.delete(socket.assigns.worker_states, service_id)

  socket =
    socket
    |> assign(:services, services)
    |> assign(:worker_states, worker_states)
    |> put_flash(:info, "Service deleted")

  {:noreply, socket}
end
```

**Step 2: Verify compilation**

Run: `mix compile --warnings-as-errors`

**Step 3: Commit**

```bash
git add lib/ethercoaster_web/live/service_live.ex
git commit -m "Add ServiceLive event handlers for play, pause, delete, save, and PubSub"
```

---

### Task 9: ScrollBottom JS hook

**Files:**
- Modify: `assets/js/app.js`

**Step 1: Add the ScrollBottom hook**

In `assets/js/app.js`, find where LiveSocket is created. Add a Hooks object:

```javascript
let Hooks = {}
Hooks.ScrollBottom = {
  mounted() {
    this.el.scrollTop = this.el.scrollHeight
  },
  updated() {
    this.el.scrollTop = this.el.scrollHeight
  }
}
```

Then pass it to the LiveSocket constructor:

```javascript
let liveSocket = new LiveSocket("/live", Socket, {
  hooks: Hooks,
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken}
})
```

**Step 2: Verify the dev server starts**

Run: `mix phx.server`
Expected: Server starts, `/services` page loads without JS errors

**Step 3: Commit**

```bash
git add assets/js/app.js
git commit -m "Add ScrollBottom JS hook for auto-scrolling log panels"
```

---

### Task 10: Add navigation link to services page

**Files:**
- Modify: `lib/ethercoaster_web/components/layouts.ex`

**Step 1: Add a Services link to the navbar**

In the `app/1` function in `lib/ethercoaster_web/components/layouts.ex`, add a nav link inside the `<ul>` alongside existing links. Add it as the first list item:

```elixir
<li>
  <a href="/services" class="btn btn-ghost">Services</a>
</li>
<li>
  <a href="/validator/query" class="btn btn-ghost">Query</a>
</li>
```

**Step 2: Commit**

```bash
git add lib/ethercoaster_web/components/layouts.ex
git commit -m "Add Services and Query links to navigation bar"
```

---

### Task 11: Integration test — create and list services

**Files:**
- Create: `test/ethercoaster/services_test.exs`

**Step 1: Write the tests**

```elixir
defmodule Ethercoaster.ServicesTest do
  use Ethercoaster.DataCase, async: true

  alias Ethercoaster.Services
  alias Ethercoaster.ValidatorRecord

  @pubkey "0x" <> String.duplicate("ab", 48)

  describe "create_service/2" do
    test "creates a service with validators" do
      # Pre-create a validator record
      Repo.insert!(%ValidatorRecord{public_key: @pubkey, index: 42})

      attrs = %{
        name: "Test Service",
        query_mode: "last_n_epochs",
        last_n_epochs: 50,
        categories: ["attestation"]
      }

      assert {:ok, service} = Services.create_service(attrs, [@pubkey])
      assert service.name == "Test Service"
      assert service.query_mode == "last_n_epochs"
      assert service.last_n_epochs == 50
      assert service.status == "stopped"
      assert length(service.validators) == 1
      assert hd(service.validators).public_key == @pubkey
    end

    test "creates a service with validator by index" do
      Repo.insert!(%ValidatorRecord{public_key: "unresolved:42", index: 42})

      attrs = %{query_mode: "epoch_range", epoch_from: 0, epoch_to: 99, categories: ["attestation"]}

      assert {:ok, service} = Services.create_service(attrs, ["42"])
      assert length(service.validators) == 1
    end
  end

  describe "list_services/0" do
    test "returns services ordered by newest first" do
      Repo.insert!(%ValidatorRecord{public_key: @pubkey, index: 42})

      {:ok, s1} = Services.create_service(
        %{name: "First", query_mode: "last_n_epochs", last_n_epochs: 10, categories: ["attestation"]},
        [@pubkey]
      )
      {:ok, s2} = Services.create_service(
        %{name: "Second", query_mode: "last_n_epochs", last_n_epochs: 20, categories: ["attestation"]},
        [@pubkey]
      )

      services = Services.list_services()
      assert length(services) == 2
      assert hd(services).id == s2.id
    end
  end

  describe "delete_service/1" do
    test "deletes a service" do
      Repo.insert!(%ValidatorRecord{public_key: @pubkey, index: 42})

      {:ok, service} = Services.create_service(
        %{name: "To Delete", query_mode: "last_n_epochs", last_n_epochs: 10, categories: ["attestation"]},
        [@pubkey]
      )

      assert {:ok, _} = Services.delete_service(service.id)
      assert Services.list_services() == []
    end
  end
end
```

**Step 2: Run the tests**

Run: `mix test test/ethercoaster/services_test.exs`
Expected: All tests pass

**Step 3: Commit**

```bash
git add test/ethercoaster/services_test.exs
git commit -m "Add Services context integration tests"
```

---

### Task 12: LiveView test — mount and create

**Files:**
- Create: `test/ethercoaster_web/live/service_live_test.exs`

**Step 1: Write LiveView tests**

```elixir
defmodule EthercoasterWeb.ServiceLiveTest do
  use EthercoasterWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "mount" do
    test "renders the services page", %{conn: conn} do
      {:ok, view, html} = live(conn, "/services")
      assert html =~ "Services"
      assert html =~ "Create Service"
    end
  end
end
```

**Step 2: Run the test**

Run: `mix test test/ethercoaster_web/live/service_live_test.exs`
Expected: Test passes

**Step 3: Commit**

```bash
git add test/ethercoaster_web/live/service_live_test.exs
git commit -m "Add ServiceLive mount test"
```

---

### Task 13: Final verification and cleanup

**Step 1: Run the full test suite**

Run: `mix test`
Expected: All tests pass

**Step 2: Verify the dev server works end-to-end**

Run: `mix phx.server`
Manual verification:
1. Navigate to `/services`
2. Add validators to the form
3. Save a service — card appears below
4. Press play — worker starts, progress updates in real time
5. Press pause — worker stops after current batch
6. Press play again — resumes from where it left off

**Step 3: Final commit (if any cleanup needed)**

```bash
git add -A
git commit -m "Services feature: final cleanup"
```
