defmodule EthercoasterWeb.CockpitLive do
  use EthercoasterWeb, :live_view

  alias Ethercoaster.Services
  alias Ethercoaster.Endpoints
  alias Ethercoaster.Validators

  @impl true
  def mount(_params, _session, socket) do
    services = Services.list_services()
    endpoints = Endpoints.list_endpoints()
    validators = Validators.list_validators()
    groups = Validators.list_groups()

    socket =
      socket
      |> assign(:service_count, length(services))
      |> assign(:service_status, status_breakdown(services))
      |> assign(:endpoint_count, length(endpoints))
      |> assign(:validator_count, length(validators))
      |> assign(:validator_states, validator_state_breakdown(validators))
      |> assign(:group_count, length(groups))
      |> assign(:supergroup_count, length(Validators.list_supergroups()))

    {:ok, socket}
  end

  defp status_breakdown(services) do
    services
    |> Enum.group_by(& &1.status)
    |> Enum.map(fn {status, list} -> {status, length(list)} end)
    |> Enum.sort_by(fn {status, _} -> status end)
  end

  defp validator_state_breakdown(validators) do
    validators
    |> Enum.group_by(fn v ->
      case v.state do
        nil -> "unknown"
        state -> state.name
      end
    end)
    |> Enum.map(fn {state, list} -> {humanize_state(state), length(list)} end)
    |> Enum.sort_by(fn {_, count} -> -count end)
  end

  defp humanize_state(name) do
    name
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
      <a href="/services" class="card bg-base-200 hover:bg-base-300 transition cursor-pointer">
        <div class="card-body">
          <h2 class="card-title">Services</h2>
          <p class="text-3xl font-bold">{@service_count}</p>
          <div class="flex flex-wrap gap-2 mt-2">
            <span :for={{status, count} <- @service_status} class="badge badge-sm badge-outline">
              {count} {status}
            </span>
          </div>
        </div>
      </a>

      <a href="/endpoints" class="card bg-base-200 hover:bg-base-300 transition cursor-pointer">
        <div class="card-body">
          <h2 class="card-title">Endpoints</h2>
          <p class="text-3xl font-bold">{@endpoint_count}</p>
          <p class="text-sm opacity-70">Saved beacon chain endpoints</p>
        </div>
      </a>

      <a href="/validators" class="card bg-base-200 hover:bg-base-300 transition cursor-pointer">
        <div class="card-body">
          <h2 class="card-title">Validators</h2>
          <p class="text-3xl font-bold">{@validator_count}</p>
          <div class="flex flex-wrap gap-2 mt-2">
            <span :for={{state, count} <- @validator_states} class="badge badge-sm badge-outline">
              {count} {state}
            </span>
          </div>
        </div>
      </a>

      <a href="/groups" class="card bg-base-200 hover:bg-base-300 transition cursor-pointer">
        <div class="card-body">
          <h2 class="card-title">Validator Groups</h2>
          <p class="text-3xl font-bold">{@group_count}</p>
          <p class="text-sm opacity-70">{@supergroup_count} supergroups</p>
        </div>
      </a>

      <a href="/reports" class="card bg-base-200 hover:bg-base-300 transition cursor-pointer">
        <div class="card-body">
          <h2 class="card-title">Financial Report</h2>
          <p class="text-sm opacity-70 mt-2">Coming soon</p>
          <p class="text-xs opacity-50">Transaction value reports in CHF/USD</p>
        </div>
      </a>
    </div>
    """
  end
end
