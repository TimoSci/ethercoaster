defmodule EthercoasterWeb.GroupsLive do
  use EthercoasterWeb, :live_view

  alias Ethercoaster.Validators

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:groups, Validators.list_groups())
      |> assign(:supergroups, Validators.list_supergroups())
      |> assign(:selected_supergroup_id, nil)
      |> assign(:group_form_error, nil)
      |> assign(:supergroup_form_error, nil)
      |> assign(:renaming_group_id, nil)
      |> assign(:renaming_supergroup_id, nil)
      |> assign(:rename_value, "")
      |> assign(:expanded_group_id, nil)
      |> assign(:expanded_supergroup_id, nil)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Validator Groups
      <:subtitle>Manage groups and supergroups of validators.</:subtitle>
    </.header>

    <div class="mt-6 grid grid-cols-1 lg:grid-cols-2 gap-6">
      <%!-- Left: Groups --%>
      <div>
        <div class="card bg-base-200 p-6 mb-4">
          <h3 class="text-lg font-semibold mb-4">Groups</h3>
          <form phx-submit="create_group" class="flex gap-2">
            <input
              type="text"
              name="name"
              class="input input-bordered flex-1"
              placeholder="New group name"
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
            class={"card p-4 transition-colors #{if in_selected_supergroup?(@supergroups, @selected_supergroup_id, group.id), do: "bg-primary/10 ring-1 ring-primary", else: "bg-base-200 hover:bg-base-300"}"}
          >
            <div class="flex items-center justify-between">
              <div
                :if={@renaming_group_id != group.id}
                phx-click="toggle_expand_group"
                phx-value-id={group.id}
                class="flex-1 cursor-pointer"
              >
                <.icon
                  name={if @expanded_group_id == group.id, do: "hero-chevron-down", else: "hero-chevron-right"}
                  class="size-3 inline-block mr-1 opacity-50"
                />
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
                <button
                  :if={@selected_supergroup_id && !in_selected_supergroup?(@supergroups, @selected_supergroup_id, group.id)}
                  phx-click="add_group_to_supergroup"
                  phx-value-group-id={group.id}
                  class="btn btn-ghost btn-xs text-success"
                  title="Add to supergroup"
                >
                  <.icon name="hero-arrow-right" class="size-3" />
                </button>
                <button
                  :if={@selected_supergroup_id && in_selected_supergroup?(@supergroups, @selected_supergroup_id, group.id)}
                  phx-click="remove_group_from_supergroup"
                  phx-value-group-id={group.id}
                  class="btn btn-ghost btn-xs text-warning"
                  title="Remove from supergroup"
                >
                  <.icon name="hero-arrow-left" class="size-3" />
                </button>
                <button phx-click="start_rename_group" phx-value-id={group.id} class="btn btn-ghost btn-xs">
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

            <div :if={@expanded_group_id == group.id && group.validators != []} class="mt-2 flex flex-wrap gap-1">
              <span
                :for={v <- group.validators}
                class="badge badge-sm badge-outline font-mono"
              >
                {display_validator(v)}
              </span>
            </div>
            <div :if={@expanded_group_id == group.id && group.validators == []} class="mt-1 text-xs opacity-50">
              No validators
            </div>
          </div>

          <div :if={@groups == []} class="text-sm opacity-50 text-center p-4">
            No groups yet. Create one above, or import validators with groups on the
            <.link navigate={~p"/validators"} class="link">Validators</.link> page.
          </div>
        </div>
      </div>

      <%!-- Right: Supergroups --%>
      <div>
        <div class="card bg-base-200 p-6 mb-4">
          <h3 class="text-lg font-semibold mb-4">Supergroups</h3>
          <p class="text-xs opacity-60 mb-3">
            A supergroup collects groups and other supergroups. Click to select, then use arrows to add groups.
          </p>
          <form phx-submit="create_supergroup" class="flex gap-2">
            <input
              type="text"
              name="name"
              class="input input-bordered flex-1"
              placeholder="New supergroup name"
            />
            <button type="submit" class="btn btn-primary btn-sm">
              <.icon name="hero-plus" class="size-4" />
            </button>
          </form>
          <p :if={@supergroup_form_error} class="text-error text-sm mt-2">{@supergroup_form_error}</p>
        </div>

        <div class="space-y-2">
          <div
            :for={sg <- @supergroups}
            class={"card p-4 cursor-pointer transition-colors #{if @selected_supergroup_id == sg.id, do: "bg-primary/10 ring-1 ring-primary", else: "bg-base-200 hover:bg-base-300"}"}
          >
            <div class="flex items-center justify-between">
              <div
                :if={@renaming_supergroup_id != sg.id}
                phx-click="select_supergroup"
                phx-value-id={sg.id}
                class="flex-1"
              >
                <span class="font-semibold">{sg.name}</span>
                <span class="badge badge-sm ml-2">
                  {length(sg.groups)} groups
                </span>
                <span class="badge badge-sm ml-1">
                  {supergroup_validator_count(sg.id)} validators
                </span>
                <span :if={sg.children != []} class="badge badge-sm badge-outline ml-1">
                  {length(sg.children)} sub
                </span>
              </div>
              <form
                :if={@renaming_supergroup_id == sg.id}
                phx-submit="rename_supergroup"
                phx-value-id={sg.id}
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
              <div :if={@renaming_supergroup_id != sg.id} class="flex gap-1">
                <button
                  phx-click="toggle_expand_supergroup"
                  phx-value-id={sg.id}
                  class="btn btn-ghost btn-xs"
                  title="Show all validators"
                >
                  <.icon name={if @expanded_supergroup_id == sg.id, do: "hero-chevron-up", else: "hero-chevron-down"} class="size-3" />
                </button>
                <button phx-click="start_rename_supergroup" phx-value-id={sg.id} class="btn btn-ghost btn-xs">
                  <.icon name="hero-pencil-square" class="size-3" />
                </button>
                <button
                  phx-click="delete_supergroup"
                  phx-value-id={sg.id}
                  data-confirm="Delete this supergroup?"
                  class="btn btn-ghost btn-xs text-error"
                >
                  <.icon name="hero-trash" class="size-3" />
                </button>
              </div>
            </div>

            <%!-- Show member groups --%>
            <div :if={@selected_supergroup_id == sg.id && sg.groups != []} class="mt-2 space-y-1">
              <p class="text-xs font-semibold opacity-60">Groups:</p>
              <div
                :for={g <- sg.groups}
                class="flex items-center justify-between text-sm bg-base-100 rounded px-2 py-1"
              >
                <span>{g.name} <span class="opacity-50">({length(g.validators)})</span></span>
                <button
                  phx-click="remove_group_from_supergroup"
                  phx-value-group-id={g.id}
                  class="btn btn-ghost btn-xs text-warning"
                  title="Remove from supergroup"
                >
                  <.icon name="hero-x-mark" class="size-3" />
                </button>
              </div>
            </div>

            <%!-- Show child supergroups --%>
            <div :if={@selected_supergroup_id == sg.id && sg.children != []} class="mt-2 space-y-1">
              <p class="text-xs font-semibold opacity-60">Child supergroups:</p>
              <div
                :for={child <- sg.children}
                class="flex items-center justify-between text-sm bg-base-100 rounded px-2 py-1"
              >
                <span>{child.name}</span>
                <button
                  phx-click="remove_child_supergroup"
                  phx-value-child-id={child.id}
                  class="btn btn-ghost btn-xs text-warning"
                  title="Remove child supergroup"
                >
                  <.icon name="hero-x-mark" class="size-3" />
                </button>
              </div>
            </div>

            <%!-- Add child supergroup controls --%>
            <div :if={@selected_supergroup_id == sg.id} class="mt-2">
              <p class="text-xs font-semibold opacity-60 mb-1">Add child supergroup:</p>
              <div class="flex flex-wrap gap-1">
                <button
                  :for={other <- available_child_supergroups(@supergroups, sg)}
                  phx-click="add_child_supergroup"
                  phx-value-child-id={other.id}
                  class="btn btn-ghost btn-xs"
                >
                  <.icon name="hero-plus" class="size-3" /> {other.name}
                </button>
                <span :if={available_child_supergroups(@supergroups, sg) == []} class="text-xs opacity-50">
                  No other supergroups available.
                </span>
              </div>
            </div>

            <%!-- Expanded: show all resolved validators --%>
            <div :if={@expanded_supergroup_id == sg.id} class="mt-3 pt-2 border-t border-base-300">
              <p class="text-xs font-semibold opacity-60 mb-1">
                All validators ({length(supergroup_all_validators(sg.id))}):
              </p>
              <div class="flex flex-wrap gap-1">
                <span
                  :for={v <- supergroup_all_validators(sg.id)}
                  class="badge badge-sm badge-outline font-mono"
                >
                  {display_validator(v)}
                </span>
                <span :if={supergroup_all_validators(sg.id) == []} class="text-xs opacity-50">
                  No validators
                </span>
              </div>
            </div>
          </div>

          <div :if={@supergroups == []} class="text-sm opacity-50 text-center p-4">
            No supergroups yet. Create one above.
          </div>
        </div>
      </div>
    </div>
    """
  end

  # --- Group events ---

  @impl true
  def handle_event("create_group", %{"name" => name}, socket) do
    case Validators.create_group(%{name: String.trim(name)}) do
      {:ok, _} ->
        {:noreply, assign(socket, groups: Validators.list_groups(), group_form_error: nil)}

      {:error, changeset} ->
        error = Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end) |> inspect()
        {:noreply, assign(socket, :group_form_error, "Validation failed: #{error}")}
    end
  end

  def handle_event("start_rename_group", %{"id" => id}, socket) do
    group = Validators.get_group!(String.to_integer(id))
    {:noreply, assign(socket, renaming_group_id: group.id, rename_value: group.name)}
  end

  def handle_event("rename_group", %{"id" => id, "name" => name}, socket) do
    group = Validators.get_group!(String.to_integer(id))

    case Validators.rename_group(group, %{name: String.trim(name)}) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:groups, Validators.list_groups())
         |> assign(:supergroups, Validators.list_supergroups())
         |> assign(:renaming_group_id, nil)
         |> assign(:rename_value, "")}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("delete_group", %{"id" => id}, socket) do
    Validators.delete_group(String.to_integer(id))

    {:noreply,
     socket
     |> assign(:groups, Validators.list_groups())
     |> assign(:supergroups, Validators.list_supergroups())}
  end

  # --- Supergroup events ---

  def handle_event("create_supergroup", %{"name" => name}, socket) do
    case Validators.create_supergroup(%{name: String.trim(name)}) do
      {:ok, _} ->
        {:noreply, assign(socket, supergroups: Validators.list_supergroups(), supergroup_form_error: nil)}

      {:error, changeset} ->
        error = Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end) |> inspect()
        {:noreply, assign(socket, :supergroup_form_error, "Validation failed: #{error}")}
    end
  end

  def handle_event("select_supergroup", %{"id" => id}, socket) do
    sg_id = String.to_integer(id)
    selected = if socket.assigns.selected_supergroup_id == sg_id, do: nil, else: sg_id
    {:noreply, assign(socket, :selected_supergroup_id, selected)}
  end

  def handle_event("start_rename_supergroup", %{"id" => id}, socket) do
    sg = Validators.get_supergroup!(String.to_integer(id))
    {:noreply, assign(socket, renaming_supergroup_id: sg.id, rename_value: sg.name)}
  end

  def handle_event("rename_supergroup", %{"id" => id, "name" => name}, socket) do
    sg = Validators.get_supergroup!(String.to_integer(id))

    case Validators.rename_supergroup(sg, %{name: String.trim(name)}) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:supergroups, Validators.list_supergroups())
         |> assign(:renaming_supergroup_id, nil)
         |> assign(:rename_value, "")}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_expand_group", %{"id" => id}, socket) do
    group_id = String.to_integer(id)
    expanded = if socket.assigns.expanded_group_id == group_id, do: nil, else: group_id
    {:noreply, assign(socket, :expanded_group_id, expanded)}
  end

  def handle_event("cancel_rename", _, socket) do
    {:noreply, assign(socket, renaming_group_id: nil, renaming_supergroup_id: nil, rename_value: "")}
  end

  def handle_event("delete_supergroup", %{"id" => id}, socket) do
    Validators.delete_supergroup(String.to_integer(id))
    sg_id = String.to_integer(id)
    selected = if socket.assigns.selected_supergroup_id == sg_id, do: nil, else: socket.assigns.selected_supergroup_id

    {:noreply,
     socket
     |> assign(:supergroups, Validators.list_supergroups())
     |> assign(:selected_supergroup_id, selected)}
  end

  def handle_event("add_group_to_supergroup", %{"group-id" => gid}, socket) do
    Validators.add_group_to_supergroup(socket.assigns.selected_supergroup_id, String.to_integer(gid))
    {:noreply, assign(socket, :supergroups, Validators.list_supergroups())}
  end

  def handle_event("remove_group_from_supergroup", %{"group-id" => gid}, socket) do
    Validators.remove_group_from_supergroup(socket.assigns.selected_supergroup_id, String.to_integer(gid))
    {:noreply, assign(socket, :supergroups, Validators.list_supergroups())}
  end

  def handle_event("add_child_supergroup", %{"child-id" => cid}, socket) do
    case Validators.add_child_supergroup(socket.assigns.selected_supergroup_id, String.to_integer(cid)) do
      :ok ->
        {:noreply, assign(socket, :supergroups, Validators.list_supergroups())}

      {:error, :circular_reference} ->
        {:noreply, put_flash(socket, :error, "Cannot add: would create a circular reference")}
    end
  end

  def handle_event("remove_child_supergroup", %{"child-id" => cid}, socket) do
    Validators.remove_child_supergroup(socket.assigns.selected_supergroup_id, String.to_integer(cid))
    {:noreply, assign(socket, :supergroups, Validators.list_supergroups())}
  end

  def handle_event("toggle_expand_supergroup", %{"id" => id}, socket) do
    sg_id = String.to_integer(id)
    expanded = if socket.assigns.expanded_supergroup_id == sg_id, do: nil, else: sg_id
    {:noreply, assign(socket, :expanded_supergroup_id, expanded)}
  end

  # --- Helpers ---

  defp in_selected_supergroup?(supergroups, selected_id, group_id) do
    case Enum.find(supergroups, &(&1.id == selected_id)) do
      nil -> false
      sg -> Enum.any?(sg.groups, &(&1.id == group_id))
    end
  end

  defp available_child_supergroups(supergroups, current) do
    existing_ids = MapSet.new(current.children, & &1.id)

    Enum.reject(supergroups, fn sg ->
      sg.id == current.id or MapSet.member?(existing_ids, sg.id)
    end)
  end

  defp supergroup_validator_count(supergroup_id) do
    length(Validators.supergroup_validators(supergroup_id))
  end

  defp supergroup_all_validators(supergroup_id) do
    Validators.supergroup_validators(supergroup_id)
  end

  defp display_validator(v) do
    cond do
      is_integer(v.index) ->
        "#{v.index}"

      is_binary(v.public_key) and String.starts_with?(v.public_key, "0x") ->
        String.slice(v.public_key, 0, 10) <> "…" <> String.slice(v.public_key, -6, 6)

      is_binary(v.public_key) and v.public_key != "" ->
        v.public_key

      true ->
        "?"
    end
  end
end
