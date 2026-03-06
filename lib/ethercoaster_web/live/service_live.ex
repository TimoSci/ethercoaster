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

  # Placeholder event handlers - will be fully implemented in Task 8
  @impl true
  def handle_info({:save_service, _params}, socket), do: {:noreply, socket}
  def handle_info({:status_change, _status}, socket), do: {:noreply, socket}
  def handle_info({:progress, _payload}, socket), do: {:noreply, socket}

  @impl true
  def handle_event("play_service", _params, socket), do: {:noreply, socket}
  def handle_event("pause_service", _params, socket), do: {:noreply, socket}
  def handle_event("delete_service", _params, socket), do: {:noreply, socket}
end
