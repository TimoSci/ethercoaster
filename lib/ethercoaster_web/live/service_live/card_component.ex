defmodule EthercoasterWeb.ServiceLive.CardComponent do
  use EthercoasterWeb, :live_component

  @impl true
  def render(assigns) do
    ws = assigns.worker_state
    status = if ws, do: ws.status, else: :stopped
    epochs_completed = if ws, do: ws.epochs_completed, else: 0
    epochs_total = if ws, do: ws.epochs_total, else: 0
    log = if ws, do: ws.log, else: []
    last_batch_ms = if ws, do: ws[:last_batch_ms], else: nil
    avg_batch_ms = if ws, do: ws[:avg_batch_ms], else: nil
    batch_started_at = if ws, do: ws[:batch_started_at], else: nil
    progress_pct = if epochs_total > 0, do: Float.round(epochs_completed / epochs_total * 100, 1), else: 0.0

    assigns =
      assigns
      |> assign(:status, status)
      |> assign(:epochs_completed, epochs_completed)
      |> assign(:epochs_total, epochs_total)
      |> assign(:log, log)
      |> assign(:progress_pct, progress_pct)
      |> assign(:last_batch_ms, last_batch_ms)
      |> assign(:avg_batch_ms, avg_batch_ms)
      |> assign(:batch_started_at, batch_started_at)

    ~H"""
    <div class="card bg-base-200 p-4">
      <div class="flex items-center justify-between mb-2">
        <div class="flex items-center gap-3">
          <h4 class="font-semibold text-lg">
            {@service.name || "Service ##{@service.id}"}
          </h4>
          <.status_badge status={@status} />
        </div>
        <div class="flex gap-1">
          <button
            :if={@status in [:stopped, :paused]}
            phx-click="play_service"
            phx-value-id={@service.id}
            class="btn btn-success btn-sm"
          >
            <.icon name="hero-play" class="size-4" />
          </button>
          <button
            :if={@status == :running}
            phx-click="pause_service"
            phx-value-id={@service.id}
            class="btn btn-warning btn-sm"
          >
            <.icon name="hero-pause" class="size-4" />
          </button>
          <.link navigate={~p"/services/#{@service.id}/edit"} class="btn btn-ghost btn-sm">
            <.icon name="hero-pencil-square" class="size-4" />
          </.link>
          <button
            phx-click="delete_service"
            phx-value-id={@service.id}
            data-confirm="Are you sure you want to delete this service?"
            class="btn btn-error btn-ghost btn-sm"
          >
            <.icon name="hero-trash" class="size-4" />
          </button>
        </div>
      </div>

      <div class="text-sm mb-2">
        <span class={endpoint_color(@endpoint_status)}>{@endpoint_url}</span>
      </div>

      <div class="text-sm opacity-70 mb-2">
        <span>{length(@service.validators)} validator(s)</span>
        <span class="mx-1">&middot;</span>
        <span :if={@service.query_mode == "last_n_epochs"}>Last {@service.last_n_epochs} epochs</span>
        <span :if={@service.query_mode == "epoch_range"}>Epochs {@service.epoch_from} – {@service.epoch_to}</span>
        <span class="mx-1">&middot;</span>
        <span :for={cat <- @service.categories} class="badge badge-sm mr-1">{cat}</span>
      </div>

      <div class="mb-2">
        <div class="flex justify-between text-xs mb-1">
          <span>{@epochs_completed} / {@epochs_total}</span>
          <span>{@progress_pct}%</span>
        </div>
        <progress class="progress progress-primary w-full" value={@epochs_completed} max={@epochs_total}></progress>
      </div>

      <div :if={@status == :running && (@last_batch_ms || @batch_started_at)} class="flex gap-4 text-xs opacity-70 mb-2">
        <span :if={@batch_started_at}>
          Current:
          <span
            id={"timer-#{@service.id}"}
            phx-hook="BatchTimer"
            data-started-at={@batch_started_at}
          >0.0s</span>
        </span>
        <span :if={@last_batch_ms}>Last: {format_ms(@last_batch_ms)}</span>
        <span :if={@avg_batch_ms}>Avg: {format_ms(@avg_batch_ms)}</span>
      </div>

      <div
        :if={@log != []}
        class="bg-base-300 rounded p-2 max-h-32 overflow-y-auto text-xs font-mono"
        id={"log-#{@service.id}"}
        phx-hook="ScrollBottom"
      >
        <div :for={entry <- @log}>{entry}</div>
      </div>
    </div>
    """
  end

  defp format_ms(nil), do: "-"
  defp format_ms(ms) when ms < 1000, do: "#{ms}ms"
  defp format_ms(ms), do: "#{Float.round(ms / 1000, 1)}s"

  defp endpoint_color(:ok), do: "text-success"
  defp endpoint_color(:error), do: "text-error"
  defp endpoint_color(_), do: "opacity-50"

  defp status_badge(assigns) do
    {color, label} =
      case assigns.status do
        :running -> {"badge-success", "Running"}
        :paused -> {"badge-warning", "Paused"}
        :completed -> {"badge-info", "Completed"}
        :error -> {"badge-error", "Error"}
        _ -> {"badge-ghost", "Stopped"}
      end

    assigns = assign(assigns, :color, color) |> assign(:label, label)

    ~H"""
    <span class={"badge badge-sm #{@color}"}>{@label}</span>
    """
  end
end
