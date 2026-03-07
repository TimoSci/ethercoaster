defmodule EthercoasterWeb.ServiceLive do
  use EthercoasterWeb, :live_view

  alias Ethercoaster.Services
  alias Ethercoaster.Service.Manager

  defp default_endpoint do
    Application.get_env(:ethercoaster, Ethercoaster.BeaconChain, [])
    |> Keyword.get(:base_url, "http://localhost:5052")
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

    socket =
      socket
      |> assign(:services, services)
      |> assign(:worker_states, worker_states)
      |> assign(:form_error, nil)
      |> assign(:endpoint_status, endpoint_status)
      |> assign(:default_endpoint, default_endpoint())

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

    <div class="mt-6 space-y-6">
      <div class="collapse collapse-arrow bg-base-200">
        <input type="checkbox" />
        <div class="collapse-title text-lg font-semibold">Create Service</div>
        <div class="collapse-content">
          <.live_component module={EthercoasterWeb.ServiceLive.FormComponent} id="service-form" form_error={@form_error} />
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

  def handle_info({:status_change, _status}, socket) do
    services = Services.list_services()

    worker_states =
      Map.new(services, fn service ->
        case Manager.get_worker_state(service.id) do
          nil ->
            prev =
              Map.get(socket.assigns.worker_states, service.id, %{
                status: String.to_atom(service.status),
                epochs_completed: 0,
                epochs_total: 0,
                log: []
              })

            {service.id, prev}

          ws ->
            {service.id, ws}
        end
      end)

    {:noreply, assign(socket, services: services, worker_states: worker_states)}
  end

  def handle_info({:progress, _payload}, socket) do
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
