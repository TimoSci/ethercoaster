defmodule EthercoasterWeb.ProgressMapLive do
  use EthercoasterWeb, :live_view

  alias Ethercoaster.Validators
  alias Ethercoaster.ProgressMap

  import EthercoasterWeb.PickerComponent

  @default_days 100
  @picker_size EthercoasterWeb.PickerComponent.picker_size()

  @impl true
  def mount(_params, _session, socket) do
    categories = ["attestation"]
    config = Application.get_env(:ethercoaster, __MODULE__, [])
    min_cell_width = Keyword.get(config, :min_cell_width, 24)

    today = Date.utc_today()

    socket =
      socket
      |> assign(:validators, [])
      |> assign(:selected_validator_ids, [])
      |> assign(:categories, categories)
      |> assign(:date_mode, :days)
      |> assign(:days, @default_days)
      |> assign(:range_from, Date.to_iso8601(Date.add(today, -30)))
      |> assign(:range_to, Date.to_iso8601(today))
      |> assign(:year, today.year)
      |> assign(:grid, nil)
      |> assign(:dates, build_dates_days(@default_days))
      |> assign(:scanning, false)
      |> assign(:min_cell_width, min_cell_width)
      |> assign(:full_width, true)
      |> assign(:saved_validators, Validators.list_validators())
      |> assign(:saved_groups, Validators.list_groups())
      |> assign(:saved_supergroups, Validators.list_supergroups())
      |> assign(:show_validator_picker, false)
      |> assign(:validator_picker_offset, 0)
      |> assign(:show_group_picker, false)
      |> assign(:group_picker_offset, 0)
      |> assign(:show_supergroup_picker, false)
      |> assign(:supergroup_picker_offset, 0)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex items-center justify-between mb-4">
      <div>
        <h2 class="text-xl font-bold">Progress Map</h2>
        <p class="text-sm opacity-70">
          {length(@validators)} validators &times; {length(@dates)} days
        </p>
      </div>
      <div class="flex items-center gap-2">
        <button phx-click="refresh_map" class="btn btn-primary btn-sm" disabled={@scanning || @validators == []}>
          {if @scanning, do: "Scanning…", else: "Refresh Map"}
        </button>
      </div>
    </div>

    <div class="flex flex-wrap items-end gap-4 mb-4">
      <%!-- Category checkboxes --%>
      <div class="flex items-center gap-2">
        <span class="text-sm font-medium">Category:</span>
        <label :for={cat <- ["attestation", "sync_committee", "block_proposal"]} class="label cursor-pointer gap-1">
          <input
            type="checkbox"
            checked={cat in @categories}
            phx-click="toggle_category"
            phx-value-category={cat}
            class="checkbox checkbox-sm checkbox-primary"
          />
          <span class="text-sm">{format_category(cat)}</span>
        </label>
      </div>

      <div class="border-l border-base-300 h-8"></div>

      <%!-- Date mode selector --%>
      <div class="flex items-center gap-2">
        <span class="text-sm font-medium">Date range:</span>
        <div class="join">
          <button
            phx-click="set_date_mode"
            phx-value-mode="days"
            class={"join-item btn btn-sm #{if @date_mode == :days, do: "btn-active", else: ""}"}
          >
            Last N days
          </button>
          <button
            phx-click="set_date_mode"
            phx-value-mode="range"
            class={"join-item btn btn-sm #{if @date_mode == :range, do: "btn-active", else: ""}"}
          >
            Range
          </button>
          <button
            phx-click="set_date_mode"
            phx-value-mode="year"
            class={"join-item btn btn-sm #{if @date_mode == :year, do: "btn-active", else: ""}"}
          >
            Year
          </button>
        </div>
      </div>

      <%!-- Mode-specific inputs --%>
      <div :if={@date_mode == :days} class="flex items-center gap-2">
        <input
          type="number"
          value={@days}
          phx-blur="update_days"
          class="input input-bordered input-sm w-20"
          min="1"
          max="1000"
        />
        <span class="text-sm opacity-70">days</span>
      </div>

      <div :if={@date_mode == :range} class="flex items-center gap-2">
        <input
          type="date"
          value={@range_from}
          phx-blur="update_range_from"
          class="input input-bordered input-sm"
        />
        <span class="text-sm opacity-70">to</span>
        <input
          type="date"
          value={@range_to}
          phx-blur="update_range_to"
          class="input input-bordered input-sm"
        />
      </div>

      <div :if={@date_mode == :year} class="flex items-center gap-2">
        <select phx-change="update_year" class="select select-bordered select-sm">
          <option :for={y <- year_options()} value={y} selected={y == @year}>{y}</option>
        </select>
      </div>
    </div>

    <%!-- Validator Filter --%>
    <div class="card bg-base-200 p-4 mb-4">
      <div class="flex items-start gap-4">
        <div class="flex-1">
          <label class="label text-sm font-semibold">Validators</label>
          <div :if={@validators != []} class="flex flex-wrap gap-1 mt-1">
            <span :for={v <- @validators} class="badge badge-sm gap-1">
              {validator_display(v)}
              <button type="button" phx-click="remove_validator" phx-value-id={v.id} class="hover:text-error">
                <.icon name="hero-x-mark" class="size-3" />
              </button>
            </span>
            <button type="button" phx-click="clear_validators" class="btn btn-ghost btn-xs">
              Clear all
            </button>
          </div>
          <p :if={@validators == []} class="text-sm opacity-50 mt-1">
            Select validators using the pickers
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

    <div class="flex gap-3 text-xs mb-2">
      <span class="flex items-center gap-1">
        <span class="inline-block w-3 h-3 rounded-sm bg-base-300 border border-base-content/10"></span> Not scanned
      </span>
      <span class="flex items-center gap-1">
        <span class="inline-block w-3 h-3 rounded-sm bg-success border border-success/30"></span> Complete
      </span>
      <span class="flex items-center gap-1">
        <span class="inline-block w-3 h-3 rounded-sm bg-warning/40 border border-warning/30"></span> Partial
      </span>
      <span class="flex items-center gap-1">
        <span class="inline-block w-3 h-3 rounded-sm bg-base-300/50 border border-base-content/5"></span> No data
      </span>
    </div>

    <div :if={@validators == []} class="text-center opacity-50 mt-12">
      Select validators, groups, or supergroups above to display the progress map.
    </div>

    <div :if={@validators != []} class="overflow-auto border border-base-300 rounded-lg" style="max-height: calc(100vh - 320px);">
      <div
        id="progress-grid"
        style={"display: grid; grid-template-columns: 80px repeat(#{length(@validators)}, minmax(#{@min_cell_width}px, 1fr)); gap: 1px; min-width: 100%;"}
      >
        <%!-- Header row: validator labels --%>
        <div class="sticky top-0 z-10 bg-base-200 text-xs font-mono p-1 text-center"></div>
        <div
          :for={v <- @validators}
          class="sticky top-0 z-10 bg-base-200 text-xs font-mono p-1 text-center truncate"
          title={validator_title(v)}
        >
          {validator_column_label(v)}
        </div>

        <%!-- Grid rows: one per date --%>
        <%= for date <- @dates do %>
          <div class="sticky left-0 z-[5] bg-base-200 text-xs font-mono p-1 whitespace-nowrap">
            {format_date(date)}
          </div>
          <%= for v <- @validators do %>
            <div
              class={cell_class(@grid, v.id, date)}
              title={"#{validator_display(v)} — #{date}"}
            >
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  # --- Picker Events ---

  @impl true
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
      |> assign(:validators, Enum.reject(socket.assigns.validators, &(&1.id == id)))
      |> assign(:grid, nil)

    {:noreply, socket}
  end

  def handle_event("clear_validators", _, socket) do
    socket =
      socket
      |> assign(:selected_validator_ids, [])
      |> assign(:validators, [])
      |> assign(:grid, nil)

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

  # --- Category / Days / Refresh ---

  def handle_event("toggle_category", %{"category" => cat}, socket) do
    categories = socket.assigns.categories

    categories =
      if cat in categories do
        List.delete(categories, cat)
      else
        categories ++ [cat]
      end

    {:noreply, assign(socket, categories: categories, grid: nil)}
  end

  def handle_event("set_date_mode", %{"mode" => mode}, socket) do
    mode = String.to_existing_atom(mode)
    dates = rebuild_dates(mode, socket.assigns)
    {:noreply, assign(socket, date_mode: mode, dates: dates, grid: nil)}
  end

  def handle_event("update_days", %{"value" => val}, socket) do
    case Integer.parse(val) do
      {days, ""} when days > 0 ->
        days = min(days, 1000)
        {:noreply, assign(socket, days: days, dates: build_dates_days(days), grid: nil)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("update_range_from", %{"value" => val}, socket) do
    case Date.from_iso8601(val) do
      {:ok, _} ->
        dates = build_dates_range(val, socket.assigns.range_to)
        {:noreply, assign(socket, range_from: val, dates: dates, grid: nil)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("update_range_to", %{"value" => val}, socket) do
    case Date.from_iso8601(val) do
      {:ok, _} ->
        dates = build_dates_range(socket.assigns.range_from, val)
        {:noreply, assign(socket, range_to: val, dates: dates, grid: nil)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("update_year", %{"value" => val}, socket) do
    case Integer.parse(val) do
      {year, ""} ->
        dates = build_dates_year(year)
        {:noreply, assign(socket, year: year, dates: dates, grid: nil)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("refresh_map", _, socket) do
    send(self(), :do_scan)
    {:noreply, assign(socket, :scanning, true)}
  end

  @impl true
  def handle_info(:do_scan, socket) do
    validators = socket.assigns.validators
    dates = socket.assigns.dates
    categories = socket.assigns.categories

    grid = ProgressMap.scan(validators, dates, categories)

    {:noreply, assign(socket, grid: grid, scanning: false)}
  end

  # --- Private Helpers ---

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
        |> assign(:validators, socket.assigns.validators ++ new_validators)
        |> assign(:grid, nil)

      {:noreply, socket}
    end
  end

  defp rebuild_dates(:days, assigns), do: build_dates_days(assigns.days)
  defp rebuild_dates(:range, assigns), do: build_dates_range(assigns.range_from, assigns.range_to)
  defp rebuild_dates(:year, assigns), do: build_dates_year(assigns.year)

  defp build_dates_days(days) do
    today = Date.utc_today()

    (days - 1)..0//-1
    |> Enum.map(&Date.add(today, -&1))
    |> Enum.map(&Date.to_iso8601/1)
  end

  defp build_dates_range(from_str, to_str) do
    with {:ok, from} <- Date.from_iso8601(from_str),
         {:ok, to} <- Date.from_iso8601(to_str),
         true <- Date.compare(from, to) != :gt do
      Date.range(from, to) |> Enum.map(&Date.to_iso8601/1)
    else
      _ -> []
    end
  end

  defp build_dates_year(year) do
    from = Date.new!(year, 1, 1)
    year_end = Date.new!(year, 12, 31)
    today = Date.utc_today()
    to = if Date.compare(year_end, today) == :gt, do: today, else: year_end

    if Date.compare(from, to) != :gt do
      Date.range(from, to) |> Enum.map(&Date.to_iso8601/1)
    else
      []
    end
  end

  defp year_options do
    current_year = Date.utc_today().year
    Enum.to_list(current_year..2020//-1)
  end

  defp format_date(date_str), do: date_str

  defp format_category("attestation"), do: "Attestation"
  defp format_category("sync_committee"), do: "Sync Committee"
  defp format_category("block_proposal"), do: "Block Proposal"

  defp validator_display(v) do
    cond do
      is_integer(v.index) -> Integer.to_string(v.index)
      is_binary(v.public_key) and String.starts_with?(v.public_key, "0x") ->
        String.slice(v.public_key, 0, 10) <> "…" <> String.slice(v.public_key, -6, 6)
      is_binary(v.public_key) and v.public_key != "" -> v.public_key
      true -> "?"
    end
  end

  defp validator_column_label(v) do
    if is_integer(v.index), do: Integer.to_string(v.index), else: validator_display(v)
  end

  defp validator_title(v) do
    parts = []
    parts = if is_integer(v.index), do: ["##{v.index}" | parts], else: parts
    parts = if is_binary(v.public_key), do: [v.public_key | parts], else: parts
    Enum.join(parts, " — ")
  end

  defp validator_picker_items(saved_validators, selected_ids) do
    excluded = MapSet.new(selected_ids)

    saved_validators
    |> Enum.reject(&MapSet.member?(excluded, &1.id))
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

  defp cell_class(nil, _vid, _date), do: "bg-base-300 min-h-[12px] border border-base-content/5"

  defp cell_class(grid, vid, date) do
    base = "min-h-[12px] border"

    case get_in(grid, [vid, date]) do
      :full -> "#{base} bg-success border-success/30"
      :partial -> "#{base} bg-warning/40 border-warning/30"
      _ -> "#{base} bg-base-300/50 border-base-content/5"
    end
  end
end
