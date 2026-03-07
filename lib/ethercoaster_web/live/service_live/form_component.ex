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
      |> assign(:mode, :create)
      |> assign(:service, nil)
      |> assign(:initialized, false)
      |> allow_upload(:validator_file, accept: ~w(.csv .json), max_entries: 1)

    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, :form_error, assigns[:form_error])
    socket = assign(socket, :saved_endpoints, assigns[:saved_endpoints] || [])

    # On first update, populate fields from service if editing
    if not socket.assigns.initialized do
      mode = assigns[:mode] || :create
      service = assigns[:service]
      socket = assign(socket, mode: mode, service: service, initialized: true)

      if mode == :edit and service do
        validators =
          case service.validators do
            [] -> [""]
            vals -> Enum.map(vals, fn v -> if v.public_key =~ ~r/\A0x/, do: v.public_key, else: Integer.to_string(v.index) end)
          end

        socket =
          socket
          |> assign(:name, service.name || "")
          |> assign(:query_mode, service.query_mode)
          |> assign(:last_n_epochs, if(service.last_n_epochs, do: Integer.to_string(service.last_n_epochs), else: ""))
          |> assign(:epoch_from, if(service.epoch_from, do: Integer.to_string(service.epoch_from), else: ""))
          |> assign(:epoch_to, if(service.epoch_to, do: Integer.to_string(service.epoch_to), else: ""))
          |> assign(:endpoint, service.endpoint || "")
          |> assign(:categories, service.categories)
          |> assign(:validators, validators)

        {:ok, socket}
      else
        {:ok, socket}
      end
    else
      {:ok, socket}
    end
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
    field_atom = String.to_existing_atom(field)
    {:noreply, assign(socket, field_atom, value)}
  end

  def handle_event("select_endpoint", %{"url" => url}, socket) do
    {:noreply, assign(socket, :endpoint, url)}
  end

  def handle_event("save", _params, socket) do
    params = build_service_params(socket)

    case socket.assigns.mode do
      :create -> send(self(), {:save_service, params})
      :edit -> send(self(), {:update_service, socket.assigns.service.id, params})
    end

    {:noreply, socket}
  end

  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("upload_validators", _params, socket) do
    uploaded =
      consume_uploaded_entries(socket, :validator_file, fn %{path: path}, entry ->
        content = File.read!(path)
        {:ok, parse_validator_file(content, entry.client_name)}
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
    save_label = if assigns.mode == :edit, do: "Update Service", else: "Save Service"
    assigns = assign(assigns, :save_label, save_label)

    ~H"""
    <div>
      <form phx-submit="save" phx-target={@myself} class="space-y-4">
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
          <div class="flex gap-2 mt-2 items-center flex-wrap">
            <button type="button" phx-click="add_validator" phx-target={@myself} class="btn btn-soft btn-sm">
              <.icon name="hero-plus" class="size-4" /> Add Validator
            </button>
            <form phx-change="validate_upload" phx-submit="upload_validators" phx-target={@myself} class="flex gap-2 items-center">
              <.live_file_input upload={@uploads.validator_file} class="file-input file-input-bordered file-input-sm" />
              <button type="submit" class="btn btn-soft btn-sm">Upload</button>
            </form>
          </div>
          <p :if={@upload_error} class="text-error text-sm mt-1">{@upload_error}</p>
        </div>

        <div>
          <label class="label">
            Transaction Categories
            <.link navigate={~p"/transaction_types"} class="ml-1 opacity-60 hover:opacity-100">
              <.icon name="hero-information-circle" class="size-4" />
            </.link>
          </label>
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

        <div>
          <label class="label">Endpoint (optional)</label>
          <div class="flex gap-2">
            <input
              type="text"
              value={@endpoint}
              phx-blur="update_field"
              phx-value-field="endpoint"
              phx-target={@myself}
              class="input input-bordered flex-1"
              placeholder="http://localhost:5052"
            />
            <div :if={@saved_endpoints != []} class="dropdown dropdown-end">
              <div tabindex="0" role="button" class="btn btn-ghost">
                <.icon name="hero-server" class="size-4" /> Saved
                <.icon name="hero-chevron-down" class="size-3" />
              </div>
              <ul tabindex="0" class="dropdown-content menu bg-base-200 rounded-box z-10 w-64 p-2 shadow-lg">
                <li :for={ep <- @saved_endpoints}>
                  <a phx-click="select_endpoint" phx-value-url={Ethercoaster.EndpointRecord.url(ep)} phx-target={@myself}>
                    {Ethercoaster.EndpointRecord.url(ep)}
                  </a>
                </li>
              </ul>
            </div>
            <.link navigate={~p"/endpoints"} class="btn btn-ghost">
              <.icon name="hero-cog-6-tooth" class="size-4" /> Manage
            </.link>
          </div>
        </div>

        <div :if={@form_error} class="alert alert-error">
          <.icon name="hero-exclamation-circle" class="size-5" />
          <span>{@form_error}</span>
        </div>

        <button type="submit" class="btn btn-primary">
          <.icon name="hero-bookmark" class="size-5" /> {@save_label}
        </button>
      </form>
    </div>
    """
  end
end
