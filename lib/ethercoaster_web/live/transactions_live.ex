defmodule EthercoasterWeb.TransactionsLive do
  use EthercoasterWeb, :live_view

  alias Ethercoaster.{Transactions, Validators}

  import EthercoasterWeb.PickerComponent

  @per_page 100
  @picker_size EthercoasterWeb.PickerComponent.picker_size()

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:sort_by, :datetime)
      |> assign(:sort_dir, :desc)
      |> assign(:page, 1)
      |> assign(:per_page, @per_page)
      |> assign(:filter_type, "")
      |> assign(:filter_category, "")
      |> assign(:filter_event, "")
      |> assign(:filter_epoch, "")
      |> assign(:selected_validator_ids, [])
      |> assign(:selected_validators, [])
      |> assign(:show_validator_picker, false)
      |> assign(:validator_picker_offset, 0)
      |> assign(:show_group_picker, false)
      |> assign(:group_picker_offset, 0)
      |> assign(:show_supergroup_picker, false)
      |> assign(:supergroup_picker_offset, 0)
      |> assign(:saved_validators, Validators.list_validators())
      |> assign(:saved_groups, Validators.list_groups())
      |> assign(:saved_supergroups, Validators.list_supergroups())
      |> assign(:type_names, Transactions.list_type_names())
      |> assign(:category_names, Transactions.list_category_names())
      |> assign(:event_names, Transactions.list_event_names())
      |> load_transactions()

    {:ok, socket}
  end

  # --- Sorting ---

  @impl true
  def handle_event("sort", %{"column" => column}, socket) do
    column = String.to_existing_atom(column)

    {sort_by, sort_dir} =
      if socket.assigns.sort_by == column do
        {column, toggle_dir(socket.assigns.sort_dir)}
      else
        {column, :asc}
      end

    socket =
      socket
      |> assign(:sort_by, sort_by)
      |> assign(:sort_dir, sort_dir)
      |> assign(:page, 1)
      |> load_transactions()

    {:noreply, socket}
  end

  # --- Column Filters ---

  def handle_event("filter", params, socket) do
    socket =
      socket
      |> assign(:filter_type, params["type"] || socket.assigns.filter_type)
      |> assign(:filter_category, params["category"] || socket.assigns.filter_category)
      |> assign(:filter_event, params["event"] || socket.assigns.filter_event)
      |> assign(:filter_epoch, params["epoch"] || socket.assigns.filter_epoch)
      |> assign(:page, 1)
      |> load_transactions()

    {:noreply, socket}
  end

  def handle_event("clear_filters", _, socket) do
    socket =
      socket
      |> assign(:filter_type, "")
      |> assign(:filter_category, "")
      |> assign(:filter_event, "")
      |> assign(:filter_epoch, "")
      |> assign(:selected_validator_ids, [])
      |> assign(:selected_validators, [])
      |> assign(:page, 1)
      |> load_transactions()

    {:noreply, socket}
  end

  # --- Pagination ---

  def handle_event("page", %{"page" => page}, socket) do
    page = String.to_integer(page)

    socket =
      socket
      |> assign(:page, page)
      |> load_transactions()

    {:noreply, socket}
  end

  # --- Validator Picker ---

  def handle_event("pick_validator", %{"item" => id_str}, socket) do
    add_validator_ids(socket, [String.to_integer(id_str)])
  end

  def handle_event("pick_group", %{"item" => group_id}, socket) do
    group = Enum.find(socket.assigns.saved_groups, &(Integer.to_string(&1.id) == group_id))

    if group do
      add_validator_ids(socket, Enum.map(group.validators, & &1.id))
    else
      {:noreply, socket}
    end
  end

  def handle_event("pick_supergroup", %{"item" => sg_id}, socket) do
    validators = Validators.supergroup_validators(String.to_integer(sg_id))
    add_validator_ids(socket, Enum.map(validators, & &1.id))
  end

  def handle_event("remove_validator", %{"id" => id_str}, socket) do
    id = String.to_integer(id_str)

    socket =
      socket
      |> assign(:selected_validator_ids, Enum.reject(socket.assigns.selected_validator_ids, &(&1 == id)))
      |> assign(:selected_validators, Enum.reject(socket.assigns.selected_validators, &(&1.id == id)))
      |> assign(:page, 1)
      |> load_transactions()

    {:noreply, socket}
  end

  def handle_event("clear_validator_filter", _, socket) do
    socket =
      socket
      |> assign(:selected_validator_ids, [])
      |> assign(:selected_validators, [])
      |> assign(:page, 1)
      |> load_transactions()

    {:noreply, socket}
  end

  # --- Generic Picker Navigation ---

  def handle_event("toggle_picker", %{"picker" => picker}, socket) do
    key = String.to_existing_atom("show_#{picker}_picker")
    {:noreply, assign(socket, key, !socket.assigns[key])}
  end

  def handle_event("picker_prev", %{"picker" => picker}, socket) do
    key = String.to_existing_atom("#{picker}_picker_offset")
    {:noreply, assign(socket, key, max(socket.assigns[key] - @picker_size, 0))}
  end

  def handle_event("picker_next", %{"picker" => picker}, socket) do
    key = String.to_existing_atom("#{picker}_picker_offset")
    {:noreply, assign(socket, key, socket.assigns[key] + @picker_size)}
  end

  # --- Private Helpers ---

  defp load_transactions(socket) do
    opts = build_query_opts(socket)
    transactions = Transactions.list_transactions(opts)
    total_count = Transactions.count_transactions(opts)
    total_pages = max(ceil(total_count / socket.assigns.per_page), 1)

    socket
    |> assign(:transactions, transactions)
    |> assign(:total_count, total_count)
    |> assign(:total_pages, total_pages)
  end

  defp build_query_opts(socket) do
    a = socket.assigns

    [
      validator_ids: a.selected_validator_ids,
      type_name: a.filter_type,
      category_name: a.filter_category,
      event_name: a.filter_event,
      epoch: a.filter_epoch,
      sort_by: a.sort_by,
      sort_dir: a.sort_dir,
      limit: a.per_page,
      offset: (a.page - 1) * a.per_page
    ]
  end

  defp add_validator_ids(socket, new_ids) do
    existing = MapSet.new(socket.assigns.selected_validator_ids)
    ids_to_add = Enum.reject(new_ids, &MapSet.member?(existing, &1))

    if ids_to_add == [] do
      {:noreply, socket}
    else
      all_ids = socket.assigns.selected_validator_ids ++ ids_to_add

      new_validators =
        socket.assigns.saved_validators
        |> Enum.filter(&(&1.id in ids_to_add))

      socket =
        socket
        |> assign(:selected_validator_ids, all_ids)
        |> assign(:selected_validators, socket.assigns.selected_validators ++ new_validators)
        |> assign(:page, 1)
        |> load_transactions()

      {:noreply, socket}
    end
  end

  defp toggle_dir(:asc), do: :desc
  defp toggle_dir(:desc), do: :asc

  defp sort_indicator(column, sort_by, sort_dir) do
    if column == sort_by do
      if sort_dir == :asc, do: " ↑", else: " ↓"
    else
      ""
    end
  end

  defp validator_display(validator) do
    cond do
      is_integer(validator.index) ->
        Integer.to_string(validator.index)

      is_binary(validator.public_key) and String.starts_with?(validator.public_key, "0x") ->
        String.slice(validator.public_key, 0, 10) <> "…" <> String.slice(validator.public_key, -6, 6)

      is_binary(validator.public_key) and validator.public_key != "" ->
        validator.public_key

      true ->
        "?"
    end
  end

  defp validator_picker_items(saved_validators, selected_ids) do
    excluded = MapSet.new(selected_ids)

    saved_validators
    |> Enum.reject(fn v -> MapSet.member?(excluded, v.id) end)
    |> Enum.map(fn v -> {Integer.to_string(v.id), validator_display(v)} end)
  end

  defp group_picker_items(saved_groups) do
    Enum.map(saved_groups, fn g ->
      count = length(g.validators)
      {Integer.to_string(g.id), "#{g.name} (#{count})"}
    end)
  end

  defp supergroup_picker_items(saved_supergroups) do
    Enum.map(saved_supergroups, fn sg ->
      {Integer.to_string(sg.id), sg.name}
    end)
  end

  defp format_amount(%Decimal{} = d), do: Decimal.to_string(d)
  defp format_amount(other), do: to_string(other)

  defp format_datetime(nil), do: "—"
  defp format_datetime(dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")

  defp has_active_filters?(assigns) do
    assigns.selected_validator_ids != [] or
      assigns.filter_type != "" or
      assigns.filter_category != "" or
      assigns.filter_event != "" or
      assigns.filter_epoch != ""
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Transactions
      <:subtitle>
        {@total_count} total transactions
        <span :if={has_active_filters?(assigns)} class="opacity-50">(filtered)</span>
      </:subtitle>
    </.header>

    <%!-- Validator Filter --%>
    <div class="card bg-base-200 p-4">
      <div class="flex items-start gap-4">
        <div class="flex-1">
          <label class="label text-sm font-semibold">Filter by Validators</label>
          <div :if={@selected_validators != []} class="flex flex-wrap gap-1 mt-1">
            <span :for={v <- @selected_validators} class="badge badge-sm gap-1">
              {validator_display(v)}
              <button type="button" phx-click="remove_validator" phx-value-id={v.id} class="hover:text-error">
                <.icon name="hero-x-mark" class="size-3" />
              </button>
            </span>
            <button type="button" phx-click="clear_validator_filter" class="btn btn-ghost btn-xs">
              Clear all
            </button>
          </div>
          <p :if={@selected_validators == []} class="text-sm opacity-50 mt-1">
            No validator filter — showing all
          </p>
        </div>
        <div class="flex gap-2 shrink-0">
          <div :if={@saved_validators != []} class="w-52">
            <.picker
              items={validator_picker_items(@saved_validators, @selected_validator_ids)}
              label="Validators"
              picker="validator"
              pick_event="pick_validator"
              show={@show_validator_picker}
              offset={@validator_picker_offset}
              empty_message="All validators selected."
            />
          </div>
          <div :if={@saved_groups != []} class="w-52">
            <.picker
              items={group_picker_items(@saved_groups)}
              label="Groups"
              picker="group"
              pick_event="pick_group"
              show={@show_group_picker}
              offset={@group_picker_offset}
            />
          </div>
          <div :if={@saved_supergroups != []} class="w-52">
            <.picker
              items={supergroup_picker_items(@saved_supergroups)}
              label="Supergroups"
              picker="supergroup"
              pick_event="pick_supergroup"
              show={@show_supergroup_picker}
              offset={@supergroup_picker_offset}
            />
          </div>
        </div>
      </div>
    </div>

    <%!-- Column Filters --%>
    <form phx-change="filter" class="flex flex-wrap gap-2 items-end">
      <div>
        <label class="label text-xs">Type</label>
        <select name="type" class="select select-bordered select-sm">
          <option value="">All types</option>
          <option :for={name <- @type_names} value={name} selected={@filter_type == name}>
            {name}
          </option>
        </select>
      </div>
      <div>
        <label class="label text-xs">Category</label>
        <select name="category" class="select select-bordered select-sm">
          <option value="">All categories</option>
          <option :for={name <- @category_names} value={name} selected={@filter_category == name}>
            {name}
          </option>
        </select>
      </div>
      <div>
        <label class="label text-xs">Event</label>
        <select name="event" class="select select-bordered select-sm">
          <option value="">All events</option>
          <option :for={name <- @event_names} value={name} selected={@filter_event == name}>
            {name}
          </option>
        </select>
      </div>
      <div>
        <label class="label text-xs">Epoch</label>
        <input
          type="number"
          name="epoch"
          value={@filter_epoch}
          class="input input-bordered input-sm w-28"
          placeholder="Any"
          min="0"
          phx-debounce="300"
        />
      </div>
      <button
        :if={has_active_filters?(assigns)}
        type="button"
        phx-click="clear_filters"
        class="btn btn-ghost btn-sm"
      >
        <.icon name="hero-x-mark" class="size-4" /> Clear filters
      </button>
    </form>

    <%!-- Transactions Table --%>
    <div class="overflow-x-auto">
      <table class="table table-zebra w-full">
        <thead>
          <tr>
            <th class="cursor-pointer hover:bg-base-300" phx-click="sort" phx-value-column="validator">
              Validator{sort_indicator(:validator, @sort_by, @sort_dir)}
            </th>
            <th class="cursor-pointer hover:bg-base-300" phx-click="sort" phx-value-column="datetime">
              Date{sort_indicator(:datetime, @sort_by, @sort_dir)}
            </th>
            <th class="cursor-pointer hover:bg-base-300" phx-click="sort" phx-value-column="amount">
              Amount{sort_indicator(:amount, @sort_by, @sort_dir)}
            </th>
            <th class="cursor-pointer hover:bg-base-300" phx-click="sort" phx-value-column="type">
              Type{sort_indicator(:type, @sort_by, @sort_dir)}
            </th>
            <th class="cursor-pointer hover:bg-base-300" phx-click="sort" phx-value-column="category">
              Category{sort_indicator(:category, @sort_by, @sort_dir)}
            </th>
            <th class="cursor-pointer hover:bg-base-300" phx-click="sort" phx-value-column="event">
              Event{sort_indicator(:event, @sort_by, @sort_dir)}
            </th>
            <th class="cursor-pointer hover:bg-base-300" phx-click="sort" phx-value-column="epoch">
              Epoch{sort_indicator(:epoch, @sort_by, @sort_dir)}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr :for={txn <- @transactions}>
            <td class="font-mono text-sm" title={txn.validator.public_key}>
              {validator_display(txn.validator)}
            </td>
            <td>{format_datetime(txn.datetime)}</td>
            <td class="font-mono">{format_amount(txn.amount)}</td>
            <td>{txn.type.name}</td>
            <td><span class="badge badge-sm">{txn.type.category.name}</span></td>
            <td>{txn.type.event.name}</td>
            <td>{txn.epoch}</td>
          </tr>
          <tr :if={@transactions == []}>
            <td colspan="7" class="text-center opacity-50 py-8">
              No transactions found.
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <%!-- Pagination --%>
    <div :if={@total_pages > 1} class="flex justify-center gap-2">
      <button
        type="button"
        phx-click="page"
        phx-value-page={@page - 1}
        class="btn btn-sm"
        disabled={@page == 1}
      >
        <.icon name="hero-chevron-left" class="size-4" /> Prev
      </button>
      <span class="flex items-center text-sm opacity-70">
        Page {@page} of {@total_pages}
      </span>
      <button
        type="button"
        phx-click="page"
        phx-value-page={@page + 1}
        class="btn btn-sm"
        disabled={@page == @total_pages}
      >
        Next <.icon name="hero-chevron-right" class="size-4" />
      </button>
    </div>
    """
  end
end
