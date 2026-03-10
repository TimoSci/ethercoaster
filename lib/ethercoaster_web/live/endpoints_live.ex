defmodule EthercoasterWeb.EndpointsLive do
  use EthercoasterWeb, :live_view

  alias Ethercoaster.Endpoints
  alias Ethercoaster.EndpointRecord

  @impl true
  def mount(_params, _session, socket) do
    default_endpoint =
      Application.get_env(:ethercoaster, Ethercoaster.BeaconChain, [])
      |> Keyword.get(:base_url, "http://localhost:5052")

    socket =
      socket
      |> assign(:endpoints, Endpoints.list_endpoints())
      |> assign(:default_endpoint, default_endpoint)
      |> assign(:editing_id, nil)
      |> assign(:form_address, "")
      |> assign(:form_port, "")
      |> assign(:form_error, nil)
      |> assign(:test_results, %{})
      |> assign(:test_logs, %{})
      |> assign(:testing_ids, MapSet.new())

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

      <div class="card bg-base-200 p-4 mb-6">
        <div class="flex items-center gap-2 text-sm">
          <span class="opacity-70">Default endpoint:</span>
          <span class="font-mono">{@default_endpoint}</span>
        </div>
      </div>

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
          <tbody :if={@endpoints == []}>
            <tr>
              <td colspan="4" class="text-center opacity-50">No endpoints saved yet.</td>
            </tr>
          </tbody>
          <tbody :for={ep <- @endpoints}>
              <tr>
                <td>{ep.address}</td>
                <td>{ep.port}</td>
                <td class={"font-mono text-sm #{test_result_class(@test_results, ep.id)}"}>{EndpointRecord.url(ep)}</td>
                <td class="flex gap-1">
                  <button
                    phx-click="test_endpoint"
                    phx-value-id={ep.id}
                    class={"btn btn-ghost btn-sm #{if ep.id in @testing_ids, do: "loading loading-spinner"}"}
                    disabled={ep.id in @testing_ids}
                    title="Test endpoint"
                  >
                    <.icon :if={ep.id not in @testing_ids} name="hero-signal" class="size-4" />
                  </button>
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
              <tr :if={Map.has_key?(@test_logs, ep.id)}>
                <td colspan="4" class="p-0">
                  <div class="bg-base-300 p-3 text-sm">
                    <div class="flex items-center justify-between mb-1">
                      <span class="font-semibold text-xs opacity-70">Test Response</span>
                      <button
                        phx-click="clear_test_log"
                        phx-value-id={ep.id}
                        class="btn btn-ghost btn-xs"
                        title="Clear log"
                      >
                        <.icon name="hero-x-mark" class="size-3" />
                      </button>
                    </div>
                    <pre class="whitespace-pre-wrap break-all font-mono text-xs opacity-80 max-h-48 overflow-auto">{@test_logs[ep.id]}</pre>
                  </div>
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

  def handle_event("test_endpoint", %{"id" => id}, socket) do
    id = String.to_integer(id)
    endpoint = Endpoints.get_endpoint!(id)
    url = EndpointRecord.url(endpoint)
    socket = update(socket, :testing_ids, &MapSet.put(&1, id))
    pid = self()

    Task.start(fn ->
      {status_kind, log} =
        try do
          case Req.get(url <> "/eth/v1/node/health", receive_timeout: 5000, connect_timeout: 5000, retry: false) do
            {:ok, %{status: status, headers: headers, body: body}} ->
              kind = if status in 200..299, do: :ok, else: :denied
              log = format_response(status, headers, body)
              {kind, log}

            {:error, %Req.TransportError{reason: reason}} ->
              {:unreachable, "Connection failed: #{inspect(reason)}"}

            {:error, error} ->
              {:unreachable, "Request failed: #{inspect(error)}"}
          end
        rescue
          e -> {:unreachable, "Error: #{Exception.message(e)}"}
        end

      send(pid, {:endpoint_tested, id, status_kind, log})
    end)

    {:noreply, socket}
  end

  def handle_event("clear_test_log", %{"id" => id}, socket) do
    id = String.to_integer(id)

    socket =
      socket
      |> update(:test_logs, &Map.delete(&1, id))
      |> update(:test_results, &Map.delete(&1, id))

    {:noreply, socket}
  end

  @impl true
  def handle_info({:endpoint_tested, id, status_kind, log}, socket) do
    socket =
      socket
      |> update(:testing_ids, &MapSet.delete(&1, id))
      |> update(:test_results, &Map.put(&1, id, status_kind))
      |> update(:test_logs, &Map.put(&1, id, log))

    {:noreply, socket}
  end

  defp format_response(status, headers, body) do
    header_lines =
      headers
      |> Enum.map(fn {k, v} -> "#{k}: #{v}" end)
      |> Enum.join("\n")

    body_str =
      case body do
        b when is_binary(b) -> b
        b when is_map(b) or is_list(b) -> Jason.encode!(b, pretty: true)
        b -> inspect(b)
      end

    "HTTP #{status}\n#{header_lines}\n\n#{body_str}"
  end

  defp test_result_class(test_results, id) do
    case Map.get(test_results, id) do
      :ok -> "text-success"
      :denied -> "text-warning"
      :unreachable -> "text-error"
      nil -> ""
    end
  end

  defp parse_port(""), do: nil

  defp parse_port(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> n
      _ -> nil
    end
  end
end
