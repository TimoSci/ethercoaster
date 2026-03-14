defmodule EthercoasterWeb.ServiceLive.FormComponent do
  use EthercoasterWeb, :live_component

  @picker_size 5

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
      |> assign(:batch_size, "")
      |> assign(:categories, ["attestation"])
      |> assign(:upload_error, nil)
      |> assign(:mode, :create)
      |> assign(:service, nil)
      |> assign(:initialized, false)
      |> assign(:show_validator_picker, false)
      |> assign(:validator_picker_offset, 0)
      |> assign(:show_group_picker, false)
      |> assign(:group_picker_offset, 0)
      |> assign(:show_endpoint_picker, false)
      |> assign(:endpoint_picker_offset, 0)
      |> allow_upload(:validator_file, accept: ~w(.csv .json), max_entries: 1)

    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, :form_error, assigns[:form_error])
    socket = assign(socket, :saved_endpoints, assigns[:saved_endpoints] || [])
    socket = assign(socket, :saved_validators, assigns[:saved_validators] || [])
    socket = assign(socket, :saved_groups, assigns[:saved_groups] || [])

    # On first update, populate fields from service if editing
    if not socket.assigns.initialized do
      mode = assigns[:mode] || :create
      service = assigns[:service]
      socket = assign(socket, mode: mode, service: service, initialized: true)

      if mode == :edit and service do
        validators =
          case service.validators do
            [] -> [""]
            vals -> Enum.map(vals, fn v ->
              cond do
                is_binary(v.public_key) and v.public_key != "" -> v.public_key
                is_integer(v.index) -> Integer.to_string(v.index)
                true -> ""
              end
            end)
          end

        socket =
          socket
          |> assign(:name, service.name || "")
          |> assign(:query_mode, service.query_mode)
          |> assign(:last_n_epochs, if(service.last_n_epochs, do: Integer.to_string(service.last_n_epochs), else: ""))
          |> assign(:epoch_from, if(service.epoch_from, do: Integer.to_string(service.epoch_from), else: ""))
          |> assign(:epoch_to, if(service.epoch_to, do: Integer.to_string(service.epoch_to), else: ""))
          |> assign(:endpoint, service.endpoint || "")
          |> assign(:batch_size, if(service.batch_size, do: Integer.to_string(service.batch_size), else: ""))
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

  def handle_event("save", _params, socket) do
    params = build_service_params(socket)

    case socket.assigns.mode do
      :create -> send(self(), {:save_service, params})
      :edit -> send(self(), {:update_service, socket.assigns.service.id, params})
    end

    {:noreply, socket}
  end

  def handle_event("validate_upload", params, socket) do
    categories = Map.get(params, "categories", [])
    {:noreply, assign(socket, :categories, categories)}
  end

  def handle_event("upload_validators", _params, socket) do
    uploaded =
      consume_uploaded_entries(socket, :validator_file, fn %{path: path}, entry ->
        content = File.read!(path)
        {:ok, Ethercoaster.ValidatorImport.parse_file(content, entry.client_name)}
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

  def handle_event("toggle_picker", %{"picker" => "validator"}, socket) do
    {:noreply, assign(socket, :show_validator_picker, !socket.assigns.show_validator_picker)}
  end

  def handle_event("toggle_picker", %{"picker" => "group"}, socket) do
    {:noreply, assign(socket, :show_group_picker, !socket.assigns.show_group_picker)}
  end

  def handle_event("toggle_picker", %{"picker" => "endpoint"}, socket) do
    {:noreply, assign(socket, :show_endpoint_picker, !socket.assigns.show_endpoint_picker)}
  end

  def handle_event("picker_prev", %{"picker" => "validator"}, socket) do
    {:noreply, assign(socket, :validator_picker_offset, max(socket.assigns.validator_picker_offset - @picker_size, 0))}
  end

  def handle_event("picker_prev", %{"picker" => "group"}, socket) do
    {:noreply, assign(socket, :group_picker_offset, max(socket.assigns.group_picker_offset - @picker_size, 0))}
  end

  def handle_event("picker_prev", %{"picker" => "endpoint"}, socket) do
    {:noreply, assign(socket, :endpoint_picker_offset, max(socket.assigns.endpoint_picker_offset - @picker_size, 0))}
  end

  def handle_event("picker_next", %{"picker" => "validator"}, socket) do
    {:noreply, assign(socket, :validator_picker_offset, socket.assigns.validator_picker_offset + @picker_size)}
  end

  def handle_event("picker_next", %{"picker" => "group"}, socket) do
    {:noreply, assign(socket, :group_picker_offset, socket.assigns.group_picker_offset + @picker_size)}
  end

  def handle_event("picker_next", %{"picker" => "endpoint"}, socket) do
    {:noreply, assign(socket, :endpoint_picker_offset, socket.assigns.endpoint_picker_offset + @picker_size)}
  end

  def handle_event("pick_validator", %{"item" => value}, socket) do
    existing = Enum.reject(socket.assigns.validators, &(&1 == ""))

    if value in existing do
      {:noreply, socket}
    else
      validators = existing ++ [value]
      {:noreply, assign(socket, validators: validators)}
    end
  end

  def handle_event("pick_group", %{"item" => group_id}, socket) do
    group = Enum.find(socket.assigns.saved_groups, &(Integer.to_string(&1.id) == group_id))

    if group do
      existing = MapSet.new(socket.assigns.validators, &String.trim/1)

      new_vals =
        group.validators
        |> Enum.map(&validator_value/1)
        |> Enum.reject(&MapSet.member?(existing, &1))

      validators = Enum.reject(socket.assigns.validators, &(&1 == "")) ++ new_vals
      validators = if validators == [], do: [""], else: validators
      {:noreply, assign(socket, :validators, validators)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("pick_endpoint", %{"item" => value}, socket) do
    {:noreply, assign(socket, :endpoint, value)}
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
        batch_size: parse_int_or_nil(a.batch_size),
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

  attr :items, :list, required: true, doc: "list of {value, display} tuples"
  attr :label, :string, required: true
  attr :picker, :string, required: true
  attr :pick_event, :string, required: true
  attr :show, :boolean, required: true
  attr :offset, :integer, required: true
  attr :target, :any, required: true
  attr :empty_message, :string, default: "No more items."

  defp picker(assigns) do
    visible = Enum.slice(assigns.items, assigns.offset, @picker_size)
    has_more = length(assigns.items) > assigns.offset + @picker_size
    assigns = assign(assigns, visible: visible, has_more: has_more)

    ~H"""
    <div>
      <button
        type="button"
        phx-click="toggle_picker"
        phx-value-picker={@picker}
        phx-target={@target}
        class="btn btn-soft btn-sm mb-2 w-full"
      >
        <.icon name={if @show, do: "hero-chevron-up", else: "hero-chevron-down"} class="size-4" />
        {@label}
      </button>
      <div :if={@show} class="bg-base-300 rounded-lg p-2 space-y-1">
        <div
          :for={{value, display} <- @visible}
          class="flex items-center justify-between bg-base-100 rounded px-2 py-1"
        >
          <span class="font-mono text-sm truncate" title={value}>
            {display}
          </span>
          <button
            type="button"
            phx-click={@pick_event}
            phx-value-item={value}
            phx-target={@target}
            class="btn btn-ghost btn-xs text-success"
            title="Select"
          >
            <.icon name="hero-arrow-left" class="size-4" />
          </button>
        </div>
        <div :if={@visible == []} class="text-xs opacity-50 text-center py-2">
          {@empty_message}
        </div>
        <div class="flex justify-between mt-1">
          <button
            type="button"
            phx-click="picker_prev"
            phx-value-picker={@picker}
            phx-target={@target}
            class="btn btn-ghost btn-xs"
            disabled={@offset == 0}
          >
            <.icon name="hero-chevron-up" class="size-3" /> Prev
          </button>
          <button
            type="button"
            phx-click="picker_next"
            phx-value-picker={@picker}
            phx-target={@target}
            class="btn btn-ghost btn-xs"
            disabled={not @has_more}
          >
            Next <.icon name="hero-chevron-down" class="size-3" />
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp validator_picker_items(saved_validators, already_added) do
    excluded = MapSet.new(already_added, &String.trim/1)

    saved_validators
    |> Enum.reject(fn v -> MapSet.member?(excluded, validator_value(v)) end)
    |> Enum.map(fn v -> {validator_value(v), validator_display(v)} end)
  end

  defp group_picker_items(saved_groups) do
    Enum.map(saved_groups, fn g ->
      count = length(g.validators)
      {Integer.to_string(g.id), "#{g.name} (#{count})"}
    end)
  end

  defp endpoint_picker_items(saved_endpoints) do
    Enum.map(saved_endpoints, fn ep ->
      url = Ethercoaster.EndpointRecord.url(ep)
      {url, url}
    end)
  end

  defp validator_value(v) do
    cond do
      is_binary(v.public_key) and v.public_key != "" -> v.public_key
      is_integer(v.index) -> Integer.to_string(v.index)
      true -> "?"
    end
  end

  defp validator_display(v) do
    cond do
      is_binary(v.public_key) and String.starts_with?(v.public_key, "0x") ->
        String.slice(v.public_key, 0, 10) <> "…" <> String.slice(v.public_key, -6, 6)
      is_binary(v.public_key) and v.public_key != "" ->
        v.public_key
      is_integer(v.index) ->
        "index: #{v.index}"
      true ->
        "?"
    end
  end

  @impl true
  def render(assigns) do
    save_label = if assigns.mode == :edit, do: "Update Service", else: "Save Service"
    assigns = assign(assigns, :save_label, save_label)

    ~H"""
    <div>
      <form phx-submit="save" phx-change="validate_upload" phx-target={@myself} class="space-y-4">
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
          <div class="flex gap-4">
            <div class="flex-1">
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
                <.live_file_input upload={@uploads.validator_file} class="file-input file-input-bordered file-input-sm" />
                <button type="button" phx-click="upload_validators" phx-target={@myself} class="btn btn-soft btn-sm">Upload</button>
              </div>
              <p :if={@upload_error} class="text-error text-sm mt-1">{@upload_error}</p>
            </div>

            <div :if={@saved_validators != [] || @saved_groups != []} class="w-64 shrink-0 space-y-2">
              <.picker
                :if={@saved_validators != []}
                items={validator_picker_items(@saved_validators, @validators)}
                label="Saved Validators"
                picker="validator"
                pick_event="pick_validator"
                show={@show_validator_picker}
                offset={@validator_picker_offset}
                target={@myself}
                empty_message="All validators already added."
              />
              <.picker
                :if={@saved_groups != []}
                items={group_picker_items(@saved_groups)}
                label="Saved Validator Groups"
                picker="group"
                pick_event="pick_group"
                show={@show_group_picker}
                offset={@group_picker_offset}
                target={@myself}
                empty_message="No groups available."
              />
            </div>
          </div>
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
              <input
                type="checkbox"
                name="categories[]"
                value="attestation"
                checked={Enum.member?(@categories, "attestation")}
                class="checkbox checkbox-primary"
              />
              <span>Attestation</span>
            </label>
            <label class="label cursor-pointer gap-2 opacity-50">
              <input type="checkbox" disabled class="checkbox" />
              <span>Sync Committee <span class="badge badge-sm">coming soon</span></span>
            </label>
            <label class="label cursor-pointer gap-2">
              <input
                type="checkbox"
                name="categories[]"
                value="block_proposal"
                checked={Enum.member?(@categories, "block_proposal")}
                class="checkbox checkbox-primary"
              />
              <span>Block Proposal</span>
            </label>
            <label class="label cursor-pointer gap-2 opacity-50">
              <input type="checkbox" disabled class="checkbox" />
              <span>Slashing <span class="badge badge-sm">coming soon</span></span>
            </label>
            <label class="label cursor-pointer gap-2 opacity-50">
              <input type="checkbox" disabled class="checkbox" />
              <span>Lifecycle <span class="badge badge-sm">coming soon</span></span>
            </label>
          </div>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-4 gap-4">
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
          <div>
            <label class="label">Batch Size</label>
            <input
              type="number"
              value={@batch_size}
              phx-blur="update_field"
              phx-value-field="batch_size"
              phx-target={@myself}
              class="input input-bordered w-full"
              min="1"
              placeholder="50"
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
          <div class="flex gap-2 items-start">
            <div class="flex-1">
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
            <div :if={@saved_endpoints != []} class="w-64 shrink-0">
              <.picker
                items={endpoint_picker_items(@saved_endpoints)}
                label="Saved Endpoints"
                picker="endpoint"
                pick_event="pick_endpoint"
                show={@show_endpoint_picker}
                offset={@endpoint_picker_offset}
                target={@myself}
              />
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
