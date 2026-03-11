defmodule EthercoasterWeb.ValidatorsLive do
  use EthercoasterWeb, :live_view

  alias Ethercoaster.Validators
  alias Ethercoaster.ValidatorImport

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:validators, Validators.list_validators())
      |> assign(:groups, Validators.list_groups())
      |> assign(:editing_id, nil)
      |> assign(:form_public_key, "")
      |> assign(:form_index, "")
      |> assign(:form_error, nil)
      |> assign(:upload_error, nil)
      |> assign(:checking_ids, MapSet.new())
      |> assign(:group_form_error, nil)
      |> assign(:renaming_group_id, nil)
      |> assign(:rename_value, "")
      |> assign(:selected_group_id, nil)
      |> allow_upload(:validator_file, accept: ~w(.csv .json), max_entries: 1, auto_upload: true)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Validators
      <:subtitle>Manage saved validator records and groups.</:subtitle>
    </.header>

    <div class="mt-6 grid grid-cols-1 lg:grid-cols-3 gap-6">
      <%!-- Left: Validators --%>
      <div class="lg:col-span-2">
        <div class="card bg-base-200 p-6 mb-6">
          <h3 class="text-lg font-semibold mb-4">
            {if @editing_id, do: "Edit Validator", else: "Add Validator"}
          </h3>
          <form phx-submit="save" phx-change="validate_upload" class="flex gap-2 items-end flex-wrap">
            <div class="flex-1 min-w-48">
              <label class="label">Public Key</label>
              <input
                type="text"
                name="public_key"
                value={@form_public_key}
                class="input input-bordered w-full"
                placeholder="0x..."
              />
            </div>
            <div class="w-32">
              <label class="label">Index</label>
              <input
                type="number"
                name="index"
                value={@form_index}
                class="input input-bordered w-full"
                min="0"
                placeholder="0"
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

          <div class="divider">or import from file</div>

          <form phx-change="validate_upload" phx-submit="upload_validators" class="flex gap-2 items-center flex-wrap">
            <.live_file_input upload={@uploads.validator_file} class="file-input file-input-bordered file-input-sm" />
            <button type="submit" class="btn btn-soft btn-sm">
              <.icon name="hero-arrow-up-tray" class="size-4" /> Import
            </button>
            <button type="button" phx-click="fuzzy_upload_validators" class="btn btn-soft btn-sm">
              <.icon name="hero-arrow-up-tray" class="size-4" /> Fuzzy Import
            </button>
            <span class="text-xs opacity-60">CSV or JSON with public keys or indices · fuzzy: more forgiving, more error prone</span>
          </form>
          <p :if={@upload_error} class="text-error text-sm mt-2">{@upload_error}</p>
        </div>

        <div class="overflow-x-auto">
          <table class="table table-zebra w-full">
            <thead>
              <tr>
                <th>Index</th>
                <th>Public Key</th>
                <th>
                  <div class="flex items-center gap-1">
                    State
                    <button
                      phx-click="check_all_states"
                      class={"btn btn-ghost btn-xs #{if @checking_ids != MapSet.new(), do: "loading loading-spinner"}"}
                      disabled={@checking_ids != MapSet.new()}
                      title="Check all states"
                    >
                      <.icon :if={@checking_ids == MapSet.new()} name="hero-arrow-path" class="size-3" />
                    </button>
                  </div>
                </th>
                <th>Created</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr :if={@validators == []}>
                <td colspan="5" class="text-center opacity-50">No validators saved yet.</td>
              </tr>
              <tr :for={v <- @validators}>
                <td>{v.index}</td>
                <td class="font-mono text-sm max-w-xs truncate">{v.public_key}</td>
                <td>
                  <div class="flex items-center gap-2">
                    <span :if={v.exists == false} class="badge badge-error badge-sm">not found</span>
                    <span :if={v.exists == true && v.state} class={"badge badge-sm #{state_badge_class(v.state.name)}"}>{v.state.name}</span>
                    <span :if={is_nil(v.exists)} class="text-xs opacity-40">—</span>
                    <button
                      phx-click="check_state"
                      phx-value-id={v.id}
                      class={"btn btn-ghost btn-xs #{if v.id in @checking_ids, do: "loading loading-spinner"}"}
                      disabled={v.id in @checking_ids}
                      title="Check state"
                    >
                      <.icon :if={v.id not in @checking_ids} name="hero-arrow-path" class="size-3" />
                    </button>
                  </div>
                </td>
                <td class="text-sm opacity-70">{Calendar.strftime(v.inserted_at, "%Y-%m-%d %H:%M")}</td>
                <td class="flex gap-1">
                  <div :if={@selected_group_id} class="flex gap-1">
                    <button
                      :if={not in_group?(@groups, @selected_group_id, v.id)}
                      phx-click="add_to_group"
                      phx-value-validator-id={v.id}
                      class="btn btn-ghost btn-sm text-success"
                      title="Add to group"
                    >
                      <.icon name="hero-arrow-right" class="size-4" />
                    </button>
                    <button
                      :if={in_group?(@groups, @selected_group_id, v.id)}
                      phx-click="remove_from_group"
                      phx-value-validator-id={v.id}
                      class="btn btn-ghost btn-sm text-warning"
                      title="Remove from group"
                    >
                      <.icon name="hero-arrow-left" class="size-4" />
                    </button>
                  </div>
                  <button phx-click="edit" phx-value-id={v.id} class="btn btn-ghost btn-sm">
                    <.icon name="hero-pencil-square" class="size-4" />
                  </button>
                  <button
                    phx-click="delete"
                    phx-value-id={v.id}
                    data-confirm="Delete this validator?"
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

      <%!-- Right: Groups --%>
      <div>
        <div class="card bg-base-200 p-6 mb-6">
          <h3 class="text-lg font-semibold mb-4">
            <.link navigate={~p"/groups"} class="link link-hover">Groups</.link>
          </h3>
          <form phx-submit="create_group" class="flex gap-2">
            <input
              type="text"
              name="name"
              class="input input-bordered flex-1"
              placeholder="Group name"
            />
            <button type="submit" class="btn btn-primary btn-sm">
              <.icon name="hero-plus" class="size-4" />
            </button>
          </form>
          <p :if={@group_form_error} class="text-error text-sm mt-2">{@group_form_error}</p>
        </div>

        <div class="space-y-2">
          <div
            :for={group <- @groups}
            class={"card p-4 cursor-pointer transition-colors #{if @selected_group_id == group.id, do: "bg-primary/10 ring-1 ring-primary", else: "bg-base-200 hover:bg-base-300"}"}
          >
            <div class="flex items-center justify-between">
              <div
                :if={@renaming_group_id != group.id}
                phx-click="select_group"
                phx-value-id={group.id}
                class="flex-1"
              >
                <span class="font-semibold">{group.name}</span>
                <span class="badge badge-sm ml-2">{length(group.validators)}</span>
              </div>
              <form
                :if={@renaming_group_id == group.id}
                phx-submit="rename_group"
                phx-value-id={group.id}
                class="flex gap-1 flex-1"
              >
                <input
                  type="text"
                  name="name"
                  value={@rename_value}
                  class="input input-bordered input-sm flex-1"
                  autofocus
                />
                <button type="submit" class="btn btn-ghost btn-sm">
                  <.icon name="hero-check" class="size-4" />
                </button>
                <button type="button" phx-click="cancel_rename" class="btn btn-ghost btn-sm">
                  <.icon name="hero-x-mark" class="size-4" />
                </button>
              </form>
              <div :if={@renaming_group_id != group.id} class="flex gap-1">
                <button phx-click="start_rename" phx-value-id={group.id} class="btn btn-ghost btn-xs">
                  <.icon name="hero-pencil-square" class="size-3" />
                </button>
                <button
                  phx-click="delete_group"
                  phx-value-id={group.id}
                  data-confirm="Delete this group?"
                  class="btn btn-ghost btn-xs text-error"
                >
                  <.icon name="hero-trash" class="size-3" />
                </button>
              </div>
            </div>

            <div :if={@selected_group_id == group.id && group.validators != []} class="mt-2 space-y-1">
              <div
                :for={v <- group.validators}
                class="flex items-center justify-between text-sm bg-base-100 rounded px-2 py-1"
              >
                <span class="font-mono truncate max-w-[12rem]">{display_validator(v)}</span>
                <button
                  phx-click="remove_from_group"
                  phx-value-validator-id={v.id}
                  class="btn btn-ghost btn-xs text-warning"
                  title="Remove from group"
                >
                  <.icon name="hero-x-mark" class="size-3" />
                </button>
              </div>
              <button
                :if={Enum.any?(group.validators, &(&1.exists == false))}
                phx-click="remove_nonexistent_from_group"
                phx-value-id={group.id}
                class="btn btn-ghost btn-xs text-error mt-1"
              >
                <.icon name="hero-trash" class="size-3" /> Remove nonexistent validators
              </button>
            </div>

            <div :if={@selected_group_id == group.id && group.validators == []} class="mt-2 text-xs opacity-50">
              No validators in this group. Use the arrow buttons to add.
            </div>
          </div>

          <div :if={@groups == []} class="text-sm opacity-50 text-center p-4">
            No groups yet. Create one above.
          </div>
        </div>
      </div>
    </div>
    """
  end

  # --- Validator events ---

  @impl true
  def handle_event("save", %{"public_key" => public_key, "index" => index}, socket) do
    public_key = String.trim(public_key)

    attrs = %{
      public_key: if(public_key != "", do: public_key, else: nil),
      index: parse_int(index)
    }

    result =
      if socket.assigns.editing_id do
        validator = Validators.get_validator!(socket.assigns.editing_id)
        Validators.update_validator(validator, attrs)
      else
        Validators.create_validator(attrs)
      end

    case result do
      {:ok, _} ->
        socket =
          socket
          |> assign(:validators, Validators.list_validators())
          |> assign(:editing_id, nil)
          |> assign(:form_public_key, "")
          |> assign(:form_index, "")
          |> assign(:form_error, nil)

        {:noreply, socket}

      {:error, changeset} ->
        error =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end) |> inspect()

        {:noreply, assign(socket, :form_error, "Validation failed: #{error}")}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    validator = Validators.get_validator!(String.to_integer(id))

    socket =
      socket
      |> assign(:editing_id, validator.id)
      |> assign(:form_public_key, validator.public_key)
      |> assign(:form_index, Integer.to_string(validator.index))
      |> assign(:form_error, nil)

    {:noreply, socket}
  end

  def handle_event("cancel_edit", _, socket) do
    socket =
      socket
      |> assign(:editing_id, nil)
      |> assign(:form_public_key, "")
      |> assign(:form_index, "")
      |> assign(:form_error, nil)

    {:noreply, socket}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    Validators.delete_validator(String.to_integer(id))

    {:noreply,
     socket
     |> assign(:validators, Validators.list_validators())
     |> assign(:groups, Validators.list_groups())}
  end

  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("upload_validators", _params, socket) do
    uploaded =
      consume_uploaded_entries(socket, :validator_file, fn %{path: path}, entry ->
        content = File.read!(path)
        {:ok, ValidatorImport.parse_file(content, entry.client_name)}
      end)

    case uploaded do
      [{:ok, parsed}] ->
        try do
          Validators.resolve_inputs(parsed)

          socket =
            socket
            |> assign(:validators, Validators.list_validators())
            |> assign(:upload_error, nil)
            |> put_flash(:info, "Imported #{length(parsed)} validator(s)")

          {:noreply, socket}
        rescue
          e ->
            {:noreply, assign(socket, :upload_error, Exception.message(e))}
        end

      [{:error, reason}] ->
        {:noreply, assign(socket, :upload_error, reason)}

      [] ->
        {:noreply, assign(socket, :upload_error, "No file selected")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("fuzzy_upload_validators", _params, socket) do
    uploaded =
      consume_uploaded_entries(socket, :validator_file, fn %{path: path}, entry ->
        content = File.read!(path)
        {:ok, ValidatorImport.fuzzy_parse_file(content, entry.client_name)}
      end)

    case uploaded do
      [{:ok, %{groups: groups, flat: flat}}] ->
        try do
          all_keys = flat ++ (groups |> Map.values() |> List.flatten())
          all_keys = Enum.uniq(all_keys)

          if all_keys == [] do
            {:noreply, assign(socket, :upload_error, "No valid public keys found in file")}
          else
            resolved = Validators.resolve_inputs(all_keys)

            # Build a lookup from public_key to validator record
            key_to_record =
              resolved
              |> Enum.filter(& &1.public_key)
              |> Map.new(&{&1.public_key, &1})

            # Create groups from JSON hierarchy
            group_counter = make_ref()
            Process.put(group_counter, 0)

            group_count =
              Enum.reduce(groups, 0, fn {name, keys}, acc ->
                group_name =
                  if name == "" do
                    n = Process.get(group_counter) + 1
                    Process.put(group_counter, n)
                    "import-#{n}"
                  else
                    name
                  end

                case Validators.create_group(%{name: group_name}) do
                  {:ok, group} ->
                    Enum.each(keys, fn key ->
                      case Map.get(key_to_record, key) do
                        %{id: vid} -> Validators.add_to_group(group.id, vid)
                        nil -> :skip
                      end
                    end)

                    acc + 1

                  {:error, _} ->
                    # Group name conflict, skip
                    acc
                end
              end)

            msg =
              "Fuzzy imported #{length(all_keys)} validator(s)" <>
                if(group_count > 0, do: " in #{group_count} group(s)", else: "")

            socket =
              socket
              |> assign(:validators, Validators.list_validators())
              |> assign(:groups, Validators.list_groups())
              |> assign(:upload_error, nil)
              |> put_flash(:info, msg)

            {:noreply, socket}
          end
        rescue
          e ->
            {:noreply, assign(socket, :upload_error, Exception.message(e))}
        end

      [{:error, reason}] ->
        {:noreply, assign(socket, :upload_error, reason)}

      [] ->
        {:noreply, assign(socket, :upload_error, "No file selected")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("check_all_states", _params, socket) do
    pid = self()
    validators = socket.assigns.validators
    ids = Enum.map(validators, & &1.id) |> MapSet.new()
    socket = assign(socket, :checking_ids, ids)

    for v <- validators do
      Task.start(fn ->
        result = Validators.check_state(v)
        send(pid, {:state_checked, v.id, result})
      end)
    end

    {:noreply, socket}
  end

  def handle_event("check_state", %{"id" => id}, socket) do
    id = String.to_integer(id)
    validator = Validators.get_validator!(id)
    socket = update(socket, :checking_ids, &MapSet.put(&1, id))

    pid = self()

    Task.start(fn ->
      result = Validators.check_state(validator)
      send(pid, {:state_checked, id, result})
    end)

    {:noreply, socket}
  end

  # --- Group events ---

  def handle_event("create_group", %{"name" => name}, socket) do
    case Validators.create_group(%{name: String.trim(name)}) do
      {:ok, _} ->
        {:noreply, assign(socket, groups: Validators.list_groups(), group_form_error: nil)}

      {:error, changeset} ->
        error =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end) |> inspect()

        {:noreply, assign(socket, :group_form_error, "Validation failed: #{error}")}
    end
  end

  def handle_event("select_group", %{"id" => id}, socket) do
    group_id = String.to_integer(id)
    selected = if socket.assigns.selected_group_id == group_id, do: nil, else: group_id
    {:noreply, assign(socket, :selected_group_id, selected)}
  end

  def handle_event("start_rename", %{"id" => id}, socket) do
    group = Validators.get_group!(String.to_integer(id))

    {:noreply,
     socket
     |> assign(:renaming_group_id, group.id)
     |> assign(:rename_value, group.name)}
  end

  def handle_event("rename_group", %{"id" => id, "name" => name}, socket) do
    group = Validators.get_group!(String.to_integer(id))

    case Validators.rename_group(group, %{name: String.trim(name)}) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:groups, Validators.list_groups())
         |> assign(:renaming_group_id, nil)
         |> assign(:rename_value, "")}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("cancel_rename", _, socket) do
    {:noreply, assign(socket, renaming_group_id: nil, rename_value: "")}
  end

  def handle_event("delete_group", %{"id" => id}, socket) do
    Validators.delete_group(String.to_integer(id))
    group_id = String.to_integer(id)
    selected = if socket.assigns.selected_group_id == group_id, do: nil, else: socket.assigns.selected_group_id

    {:noreply,
     socket
     |> assign(:groups, Validators.list_groups())
     |> assign(:selected_group_id, selected)}
  end

  def handle_event("add_to_group", %{"validator-id" => vid}, socket) do
    Validators.add_to_group(socket.assigns.selected_group_id, String.to_integer(vid))
    {:noreply, assign(socket, :groups, Validators.list_groups())}
  end

  def handle_event("remove_from_group", %{"validator-id" => vid}, socket) do
    Validators.remove_from_group(socket.assigns.selected_group_id, String.to_integer(vid))
    {:noreply, assign(socket, :groups, Validators.list_groups())}
  end

  def handle_event("remove_nonexistent_from_group", %{"id" => id}, socket) do
    group_id = String.to_integer(id)
    group = Validators.get_group!(group_id)

    Enum.each(group.validators, fn v ->
      if v.exists == false, do: Validators.remove_from_group(group_id, v.id)
    end)

    {:noreply, assign(socket, :groups, Validators.list_groups())}
  end

  @impl true
  def handle_info({:state_checked, id, result}, socket) do
    socket = update(socket, :checking_ids, &MapSet.delete(&1, id))

    socket =
      case result do
        {:ok, _} ->
          assign(socket, :validators, Validators.list_validators())

        {:error, reason} ->
          put_flash(socket, :error, "Failed to check state: #{inspect(reason)}")
      end

    {:noreply, socket}
  end

  # --- Helpers ---

  defp in_group?(groups, group_id, validator_id) do
    case Enum.find(groups, &(&1.id == group_id)) do
      nil -> false
      group -> Enum.any?(group.validators, &(&1.id == validator_id))
    end
  end

  defp display_validator(v) do
    cond do
      is_binary(v.public_key) and String.starts_with?(v.public_key, "0x") ->
        String.slice(v.public_key, 0, 10) <> "…" <> String.slice(v.public_key, -6, 6)
      is_binary(v.public_key) and v.public_key != "" ->
        v.public_key
      is_integer(v.index) ->
        "#{v.index}"
      true ->
        "?"
    end
  end

  defp state_badge_class(name) do
    cond do
      String.starts_with?(name, "active") -> "badge-success"
      String.starts_with?(name, "pending") -> "badge-warning"
      String.starts_with?(name, "exited") -> "badge-info"
      String.starts_with?(name, "withdrawal") -> "badge-neutral"
      true -> ""
    end
  end

  defp parse_int(""), do: nil

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> n
      _ -> nil
    end
  end
end
