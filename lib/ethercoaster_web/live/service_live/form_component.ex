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
    field_atom = String.to_existing_atom(field)
    {:noreply, assign(socket, field_atom, value)}
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
          <div class="flex gap-2 mt-2 items-center">
            <button type="button" phx-click="add_validator" phx-target={@myself} class="btn btn-soft btn-sm">
              <.icon name="hero-plus" class="size-4" /> Add Validator
            </button>
          </div>
          <p :if={@upload_error} class="text-error text-sm mt-1">{@upload_error}</p>
        </div>

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

        <div :if={@form_error} class="alert alert-error">
          <.icon name="hero-exclamation-circle" class="size-5" />
          <span>{@form_error}</span>
        </div>

        <button type="submit" class="btn btn-primary">
          <.icon name="hero-bookmark" class="size-5" /> Save Service
        </button>
      </form>

      <form phx-change="validate_upload" phx-submit="upload_validators" phx-target={@myself} class="flex gap-2 items-center mt-2">
        <.live_file_input upload={@uploads.validator_file} class="file-input file-input-bordered file-input-sm" />
        <button type="submit" class="btn btn-soft btn-sm">Upload Validators</button>
      </form>
    </div>
    """
  end
end
