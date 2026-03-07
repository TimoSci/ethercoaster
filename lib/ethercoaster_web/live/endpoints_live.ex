defmodule EthercoasterWeb.EndpointsLive do
  use EthercoasterWeb, :live_view

  alias Ethercoaster.Endpoints
  alias Ethercoaster.EndpointRecord

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:endpoints, Endpoints.list_endpoints())
      |> assign(:editing_id, nil)
      |> assign(:form_address, "")
      |> assign(:form_port, "")
      |> assign(:form_error, nil)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Endpoints
      <:subtitle>Manage saved beacon chain endpoints.</:subtitle>
    </.header>

    <div class="mt-6">
      <button onclick="history.back()" class="btn btn-ghost btn-sm mb-4">
        <.icon name="hero-arrow-left" class="size-4" /> Back
      </button>

      <div class="card bg-base-200 p-6 mb-6">
        <h3 class="text-lg font-semibold mb-4">
          {if @editing_id, do: "Edit Endpoint", else: "Add Endpoint"}
        </h3>
        <form phx-submit="save" class="flex gap-2 items-end">
          <div class="flex-1">
            <label class="label">Address</label>
            <input
              type="text"
              name="address"
              value={@form_address}
              class="input input-bordered w-full"
              placeholder="http://localhost"
            />
          </div>
          <div class="w-32">
            <label class="label">Port</label>
            <input
              type="number"
              name="port"
              value={@form_port}
              class="input input-bordered w-full"
              min="1"
              max="65535"
              placeholder="5052"
            />
          </div>
          <button type="submit" class="btn btn-primary">
            <.icon name={if @editing_id, do: "hero-check", else: "hero-plus"} class="size-4" />
            {if @editing_id, do: "Update", else: "Add"}
          </button>
          <button :if={@editing_id} type="button" phx-click="cancel_edit" class="btn btn-ghost">
            Cancel
          </button>
        </form>
        <p :if={@form_error} class="text-error text-sm mt-2">{@form_error}</p>
      </div>

      <div class="overflow-x-auto">
        <table class="table table-zebra w-full">
          <thead>
            <tr>
              <th>Address</th>
              <th>Port</th>
              <th>URL</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr :if={@endpoints == []}>
              <td colspan="4" class="text-center opacity-50">No endpoints saved yet.</td>
            </tr>
            <tr :for={ep <- @endpoints}>
              <td>{ep.address}</td>
              <td>{ep.port}</td>
              <td class="font-mono text-sm">{EndpointRecord.url(ep)}</td>
              <td class="flex gap-1">
                <button phx-click="edit" phx-value-id={ep.id} class="btn btn-ghost btn-sm">
                  <.icon name="hero-pencil-square" class="size-4" />
                </button>
                <button
                  phx-click="delete"
                  phx-value-id={ep.id}
                  data-confirm="Delete this endpoint?"
                  class="btn btn-ghost btn-sm text-error"
                >
                  <.icon name="hero-trash" class="size-4" />
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("save", %{"address" => address, "port" => port}, socket) do
    attrs = %{address: String.trim(address), port: parse_port(port)}

    result =
      if socket.assigns.editing_id do
        endpoint = Endpoints.get_endpoint!(socket.assigns.editing_id)
        Endpoints.update_endpoint(endpoint, attrs)
      else
        Endpoints.create_endpoint(attrs)
      end

    case result do
      {:ok, _} ->
        socket =
          socket
          |> assign(:endpoints, Endpoints.list_endpoints())
          |> assign(:editing_id, nil)
          |> assign(:form_address, "")
          |> assign(:form_port, "")
          |> assign(:form_error, nil)

        {:noreply, socket}

      {:error, changeset} ->
        error =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end) |> inspect()

        {:noreply, assign(socket, :form_error, "Validation failed: #{error}")}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    endpoint = Endpoints.get_endpoint!(String.to_integer(id))

    socket =
      socket
      |> assign(:editing_id, endpoint.id)
      |> assign(:form_address, endpoint.address)
      |> assign(:form_port, Integer.to_string(endpoint.port))
      |> assign(:form_error, nil)

    {:noreply, socket}
  end

  def handle_event("cancel_edit", _, socket) do
    socket =
      socket
      |> assign(:editing_id, nil)
      |> assign(:form_address, "")
      |> assign(:form_port, "")
      |> assign(:form_error, nil)

    {:noreply, socket}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    Endpoints.delete_endpoint(String.to_integer(id))

    {:noreply, assign(socket, :endpoints, Endpoints.list_endpoints())}
  end

  defp parse_port(""), do: nil

  defp parse_port(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> n
      _ -> nil
    end
  end
end
