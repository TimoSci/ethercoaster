defmodule EthercoasterWeb.ServiceLive do
  use EthercoasterWeb, :live_view

  alias Ethercoaster.Services
  alias Ethercoaster.Endpoints
  alias Ethercoaster.Validators
  alias Ethercoaster.Service.Manager
  alias Ethercoaster.ProgressMap

  @progress_map_days 14

  defp default_endpoint do
    Application.get_env(:ethercoaster, Ethercoaster.BeaconChain, [])
    |> Keyword.get(:base_url, "http://localhost:5052")
  end

  defp endpoints_with_default do
    alias Ethercoaster.EndpointRecord

    db_endpoints = Endpoints.list_endpoints()
    default_url = default_endpoint()
    db_urls = Enum.map(db_endpoints, &EndpointRecord.url/1)

    if default_url in db_urls do
      db_endpoints
    else
      case EndpointRecord.parse_url(default_url) do
        {:ok, attrs} ->
          pseudo = %EndpointRecord{id: nil, address: attrs.address, port: attrs.port}
          [pseudo | db_endpoints]

        _ ->
          db_endpoints
      end
    end
  end

  defp effective_endpoint(service) do
    service.endpoint || default_endpoint()
  end

  @impl true
  def mount(_params, _session, socket) do
    services = Services.list_services()

    if connected?(socket) do
      for service <- services do
        Phoenix.PubSub.subscribe(Ethercoaster.PubSub, "service:#{service.id}")
      end

      check_all_endpoints(services)
    end

    worker_states =
      Map.new(services, fn service ->
        case Manager.get_worker_state(service.id) do
          nil ->
            {service.id, %{status: String.to_atom(service.status), epochs_completed: 0, epochs_total: 0, log: []}}
          ws ->
            {service.id, ws}
        end
      end)

    # endpoint_status: %{service_id => :ok | :error | :checking}
    endpoint_status = Map.new(services, fn s -> {s.id, :checking} end)

    validators_by_index = Validators.list_validators_by_index()
    progress_map_dates = build_recent_dates(@progress_map_days)
    progress_map_grid = ProgressMap.scan(validators_by_index, progress_map_dates, ["attestation"])

    socket =
      socket
      |> assign(:services, services)
      |> assign(:worker_states, worker_states)
      |> assign(:form_error, nil)
      |> assign(:endpoint_status, endpoint_status)
      |> assign(:default_endpoint, default_endpoint())
      |> assign(:saved_endpoints, endpoints_with_default())
      |> assign(:saved_validators, validators_by_index)
      |> assign(:progress_map_validators, validators_by_index)
      |> assign(:progress_map_days, @progress_map_days)
      |> assign(:progress_map_dates, progress_map_dates)
      |> assign(:progress_map_grid, progress_map_grid)

    {:ok, socket}
  end

  defp check_all_endpoints(services) do
    lv = self()

    for service <- services do
      endpoint = effective_endpoint(service)
      service_id = service.id

      Task.start(fn ->
        result = check_endpoint(endpoint)
        send(lv, {:endpoint_check, service_id, result})
      end)
    end
  end

  defp build_recent_dates(days) do
    today = Date.utc_today()

    (days - 1)..0//-1
    |> Enum.map(&Date.add(today, -&1))
    |> Enum.map(&Date.to_iso8601/1)
  end

  defp progress_cell_color(nil, _vid, _date), do: "bg-base-300"

  defp progress_cell_color(grid, vid, date) do
    case get_in(grid, [vid, date]) do
      :full -> "bg-success"
      :partial -> "bg-warning/40"
      _ -> "bg-base-300/50"
    end
  end

  defp check_endpoint(base_url) do
    try do
      req = Req.new(base_url: base_url, receive_timeout: 5_000, finch: Ethercoaster.Finch)

      case Req.get(req, url: "/eth/v1/node/syncing") do
        {:ok, %Req.Response{status: status}} when status in 200..299 -> :ok
        _ -> :error
      end
    rescue
      _ -> :error
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Services
      <:subtitle>Create and manage background validator reward queries.</:subtitle>
    </.header>

    <a href="/services/progress_map" class="card bg-base-200 hover:bg-base-300 transition cursor-pointer mt-6 block">
      <div class="card-body py-4">
        <div class="flex items-center justify-between">
          <div>
            <h2 class="card-title text-base">Progress Map</h2>
            <p class="text-xs opacity-70">
              {length(@progress_map_validators)} validators &times; {@progress_map_days} days &middot; attestation
            </p>
          </div>
          <span class="text-sm opacity-50">&rsaquo;</span>
        </div>
        <div
          :if={@progress_map_validators != []}
          class="mt-2 overflow-hidden rounded"
          style={"display:grid; grid-template-columns:repeat(#{length(@progress_map_validators)}, 1fr);"}
        >
          <%= for date <- @progress_map_dates do %>
            <div
              :for={v <- @progress_map_validators}
              class={"h-px #{progress_cell_color(@progress_map_grid, v.id, date)}"}
            >
            </div>
          <% end %>
        </div>
        <p :if={@progress_map_validators == []} class="text-xs opacity-50 mt-2">
          No validators added yet.
        </p>
      </div>
    </a>

    <div class="mt-4 space-y-6">
      <div class="collapse collapse-arrow bg-base-200">
        <input type="checkbox" />
        <div class="collapse-title text-lg font-semibold">Create Service</div>
        <div class="collapse-content">
          <.live_component module={EthercoasterWeb.ServiceLive.FormComponent} id="service-form" form_error={@form_error} saved_endpoints={@saved_endpoints} saved_validators={@saved_validators} />
        </div>
      </div>

      <div class="space-y-4">
        <div :for={service <- @services} id={"service-#{service.id}"}>
          <.live_component
            module={EthercoasterWeb.ServiceLive.CardComponent}
            id={"card-#{service.id}"}
            service={service}
            worker_state={Map.get(@worker_states, service.id)}
            endpoint_url={service.endpoint || @default_endpoint}
            endpoint_status={Map.get(@endpoint_status, service.id, :checking)}
          />
        </div>
      </div>
    </div>
    """
  end

  # --- Endpoint checks ---

  @impl true
  def handle_info({:endpoint_check, service_id, result}, socket) do
    endpoint_status = Map.put(socket.assigns.endpoint_status, service_id, result)
    {:noreply, assign(socket, :endpoint_status, endpoint_status)}
  end

  # --- Form save ---

  def handle_info({:save_service, params}, socket) do
    # Auto-save manually entered endpoint
    if params.attrs[:endpoint] && params.attrs.endpoint != "" do
      Endpoints.ensure_from_url(params.attrs.endpoint)
    end

    case Services.create_service(params.attrs, params.validators) do
      {:ok, service} ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(Ethercoaster.PubSub, "service:#{service.id}")
        end

        services = [service | socket.assigns.services]

        worker_states =
          Map.put(socket.assigns.worker_states, service.id, %{
            status: :stopped,
            epochs_completed: 0,
            epochs_total: 0,
            log: []
          })

        endpoint_status = Map.put(socket.assigns.endpoint_status, service.id, :checking)

        if connected?(socket) do
          endpoint = effective_endpoint(service)
          sid = service.id
          lv = self()
          Task.start(fn ->
            result = check_endpoint(endpoint)
            send(lv, {:endpoint_check, sid, result})
          end)
        end

        socket =
          socket
          |> assign(:services, services)
          |> assign(:worker_states, worker_states)
          |> assign(:endpoint_status, endpoint_status)
          |> assign(:saved_endpoints, endpoints_with_default())
          |> assign(:form_error, nil)
          |> put_flash(:info, "Service created")

        {:noreply, socket}

      {:error, changeset} when is_struct(changeset, Ecto.Changeset) ->
        error =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end) |> inspect()

        {:noreply, assign(socket, :form_error, "Validation failed: #{error}")}

      {:error, reason} ->
        {:noreply, assign(socket, :form_error, "Error: #{inspect(reason)}")}
    end
  end

  # --- PubSub handlers ---

  def handle_info({:status_change, snapshot}, socket) do
    services = Services.list_services()
    worker_states = update_worker_state(socket.assigns.worker_states, snapshot)
    {:noreply, assign(socket, services: services, worker_states: worker_states)}
  end

  def handle_info({:batch_started, snapshot}, socket) do
    {:noreply, assign(socket, :worker_states, update_worker_state(socket.assigns.worker_states, snapshot))}
  end

  def handle_info({:progress, snapshot}, socket) do
    {:noreply, assign(socket, :worker_states, update_worker_state(socket.assigns.worker_states, snapshot))}
  end

  defp update_worker_state(worker_states, snapshot) do
    prev = Map.get(worker_states, snapshot.service_id)

    # Don't overwrite a locally-set :paused status while worker finishes its batch
    if prev && prev.status == :paused do
      worker_states
    else
      Map.put(worker_states, snapshot.service_id, snapshot)
    end
  end

  # --- User actions ---

  @impl true
  def handle_event("play_service", %{"id" => id}, socket) do
    service_id = String.to_integer(id)

    case Manager.start_service(service_id) do
      {:ok, _pid} ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(Ethercoaster.PubSub, "service:#{service_id}")
        end

        worker_states =
          Map.put(socket.assigns.worker_states, service_id, %{
            status: :running,
            epochs_completed: 0,
            epochs_total: 0,
            log: ["Starting..."]
          })

        {:noreply, assign(socket, :worker_states, worker_states)}

      {:error, :already_running} ->
        {:noreply, put_flash(socket, :info, "Service is already running")}
    end
  end

  def handle_event("pause_service", %{"id" => id}, socket) do
    service_id = String.to_integer(id)
    Manager.stop_service(service_id)

    worker_states =
      Map.update(socket.assigns.worker_states, service_id, %{status: :paused, epochs_completed: 0, epochs_total: 0, log: []}, fn ws ->
        Map.put(ws, :status, :paused)
      end)

    {:noreply, assign(socket, :worker_states, worker_states)}
  end

  def handle_event("delete_service", %{"id" => id}, socket) do
    service_id = String.to_integer(id)
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
end
