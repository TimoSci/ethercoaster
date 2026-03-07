defmodule EthercoasterWeb.ProgressMapLive do
  use EthercoasterWeb, :live_view

  alias Ethercoaster.Validators
  alias Ethercoaster.ProgressMap

  @default_days 100

  @impl true
  def mount(_params, _session, socket) do
    validators = Validators.list_validators_by_index()
    categories = ["attestation"]

    socket =
      socket
      |> assign(:validators, validators)
      |> assign(:categories, categories)
      |> assign(:days, @default_days)
      |> assign(:grid, nil)
      |> assign(:dates, build_dates(@default_days))
      |> assign(:scanning, false)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex items-center justify-between mb-4">
      <div>
        <h2 class="text-xl font-bold">Progress Map</h2>
        <p class="text-sm opacity-70">
          {length(@validators)} validators &times; {@days} days
        </p>
      </div>
      <div class="flex items-center gap-4">
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
        <div class="flex items-center gap-2">
          <span class="text-sm font-medium">Days:</span>
          <input
            type="number"
            value={@days}
            phx-blur="update_days"
            phx-value-field="days"
            class="input input-bordered input-sm w-20"
            min="1"
            max="1000"
          />
        </div>
        <button phx-click="refresh_map" class="btn btn-primary btn-sm" disabled={@scanning || @validators == []}>
          {if @scanning, do: "Scanning…", else: "Refresh Map"}
        </button>
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
      No validators in database. Add validators first.
    </div>

    <div :if={@validators != []} class="overflow-auto border border-base-300 rounded-lg" style="max-height: calc(100vh - 220px);">
      <div
        id="progress-grid"
        style={"display: grid; grid-template-columns: 60px repeat(#{length(@validators)}, 1fr); gap: 1px;"}
      >
        <%!-- Header row: validator indices --%>
        <div class="sticky top-0 z-10 bg-base-200 text-xs font-mono p-1 text-center"></div>
        <div
          :for={v <- @validators}
          class="sticky top-0 z-10 bg-base-200 text-xs font-mono p-1 text-center truncate"
          title={"Validator #{v.index}"}
        >
          {v.index}
        </div>

        <%!-- Grid rows: one per date --%>
        <%= for date <- @dates do %>
          <div class="sticky left-0 z-[5] bg-base-200 text-xs font-mono p-1 whitespace-nowrap">
            {format_date(date)}
          </div>
          <%= for v <- @validators do %>
            <div
              class={cell_class(@grid, v.id, date)}
              title={"Validator #{v.index} — #{date}"}
            >
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
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

  def handle_event("update_days", %{"value" => val}, socket) do
    case Integer.parse(val) do
      {days, ""} when days > 0 ->
        days = min(days, 1000)
        {:noreply, assign(socket, days: days, dates: build_dates(days), grid: nil)}

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

  # --- Helpers ---

  defp build_dates(days) do
    today = Date.utc_today()

    (days - 1)..0//-1
    |> Enum.map(&Date.add(today, -&1))
    |> Enum.map(&Date.to_iso8601/1)
  end

  defp format_date(date_str) do
    {:ok, date} = Date.from_iso8601(date_str)
    Calendar.strftime(date, "%m/%d")
  end

  defp format_category("attestation"), do: "Attestation"
  defp format_category("sync_committee"), do: "Sync Committee"
  defp format_category("block_proposal"), do: "Block Proposal"

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
