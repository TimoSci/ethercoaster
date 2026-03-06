defmodule EthercoasterWeb.ServiceLive do
  use EthercoasterWeb, :live_view

  alias Ethercoaster.Services
  alias Ethercoaster.Service.Manager

  @impl true
  def mount(_params, _session, socket) do
    services = Services.list_services()

    if connected?(socket) do
      for service <- services do
        Phoenix.PubSub.subscribe(Ethercoaster.PubSub, "service:#{service.id}")
      end
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

    socket =
      socket
      |> assign(:services, services)
      |> assign(:worker_states, worker_states)
      |> assign(:form_error, nil)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Services
      <:subtitle>Create and manage background validator reward queries.</:subtitle>
    </.header>

    <div class="mt-6 space-y-6">
      <div class="card bg-base-200 p-6">
        <h3 class="text-lg font-semibold mb-4">Create Service</h3>
        <.live_component module={EthercoasterWeb.ServiceLive.FormComponent} id="service-form" form_error={@form_error} />
      </div>

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

  # --- Form save ---

  @impl true
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

        socket =
          socket
          |> assign(:services, services)
          |> assign(:worker_states, worker_states)
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
