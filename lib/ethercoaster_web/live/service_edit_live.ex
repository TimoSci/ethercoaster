defmodule EthercoasterWeb.ServiceEditLive do
  use EthercoasterWeb, :live_view

  alias Ethercoaster.Services
  alias Ethercoaster.Endpoints
  alias Ethercoaster.Validators

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    service = Services.get_service!(id)

    socket =
      socket
      |> assign(:service, service)
      |> assign(:form_error, nil)
      |> assign(:saved_endpoints, Endpoints.list_endpoints())
      |> assign(:saved_validators, Validators.list_validators_by_index())

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Edit Service
      <:subtitle>{@service.name || "Service ##{@service.id}"}</:subtitle>
    </.header>

    <div class="mt-6">
      <.link navigate={~p"/services"} class="btn btn-ghost btn-sm mb-4">
        <.icon name="hero-arrow-left" class="size-4" /> Back to Services
      </.link>

      <div class="card bg-base-200 p-6">
        <.live_component
          module={EthercoasterWeb.ServiceLive.FormComponent}
          id="service-edit-form"
          mode={:edit}
          service={@service}
          form_error={@form_error}
          saved_endpoints={@saved_endpoints}
          saved_validators={@saved_validators}
        />
      </div>
    </div>
    """
  end

  @impl true
  def handle_info({:update_service, id, params}, socket) do
    if params.attrs[:endpoint] && params.attrs.endpoint != "" do
      Endpoints.ensure_from_url(params.attrs.endpoint)
    end

    service = Services.get_service!(id)

    case Services.update_service(service, params.attrs, params.validators) do
      {:ok, _service} ->
        socket =
          socket
          |> put_flash(:info, "Service updated")
          |> push_navigate(to: ~p"/services")

        {:noreply, socket}

      {:error, changeset} when is_struct(changeset, Ecto.Changeset) ->
        error =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end) |> inspect()

        {:noreply, assign(socket, :form_error, "Validation failed: #{error}")}

      {:error, reason} ->
        {:noreply, assign(socket, :form_error, "Error: #{inspect(reason)}")}
    end
  end
end
