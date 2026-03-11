# Cockpit Page Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Phoenix welcome page with a cockpit dashboard showing 5 summary cards linking to top-level pages.

**Architecture:** A `CockpitLive` LiveView queries existing context modules on mount for counts/status breakdowns and renders them as DaisyUI cards in a responsive grid. Two placeholder LiveViews (`GroupsLive`, `ReportsLive`) are added for future pages. The `PageController` and its templates are removed.

**Tech Stack:** Phoenix LiveView, DaisyUI (Tailwind), Elixir/Ecto

---

## File Structure

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `lib/ethercoaster_web/live/cockpit_live.ex` | Cockpit dashboard LiveView — queries summary data on mount, renders card grid |
| Create | `lib/ethercoaster_web/live/groups_live.ex` | Placeholder page for validator groups |
| Create | `lib/ethercoaster_web/live/reports_live.ex` | Placeholder page for financial reports |
| Modify | `lib/ethercoaster_web/router.ex` | Replace `get "/"` with `live "/"`, add `/groups` and `/reports` routes |
| Delete | `lib/ethercoaster_web/controllers/page_controller.ex` | No longer needed |
| Delete | `lib/ethercoaster_web/controllers/page_html.ex` | No longer needed |
| Delete | `lib/ethercoaster_web/controllers/page_html/home.html.heex` | No longer needed |

---

## Chunk 1: Placeholder LiveViews and Router Changes

### Task 1: Create GroupsLive placeholder

**Files:**
- Create: `lib/ethercoaster_web/live/groups_live.ex`

- [ ] **Step 1: Create the GroupsLive module**

```elixir
defmodule EthercoasterWeb.GroupsLive do
  use EthercoasterWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Validator Groups
      <:subtitle>Group management coming soon.</:subtitle>
    </.header>
    """
  end
end
```

- [ ] **Step 2: Verify it compiles**

Run: `mix compile`
Expected: Success, no errors

### Task 2: Create ReportsLive placeholder

**Files:**
- Create: `lib/ethercoaster_web/live/reports_live.ex`

- [ ] **Step 1: Create the ReportsLive module**

```elixir
defmodule EthercoasterWeb.ReportsLive do
  use EthercoasterWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Financial Report
      <:subtitle>Transaction value reports coming soon.</:subtitle>
    </.header>
    """
  end
end
```

- [ ] **Step 2: Verify it compiles**

Run: `mix compile`
Expected: Success, no errors

### Task 3: Update router — add new routes, remove PageController

**Files:**
- Modify: `lib/ethercoaster_web/router.ex`
- Delete: `lib/ethercoaster_web/controllers/page_controller.ex`
- Delete: `lib/ethercoaster_web/controllers/page_html.ex`
- Delete: `lib/ethercoaster_web/controllers/page_html/home.html.heex`

- [ ] **Step 1: Update the router**

In `lib/ethercoaster_web/router.ex`, remove this line:

```elixir
    get "/", PageController, :home
```

Then add `live "/", CockpitLive` and the two placeholder routes inside the existing `live_session :default` block, so it becomes:

```elixir
    live_session :default,
      on_mount: [EthercoasterWeb.Hooks.SetPath],
      layout: {EthercoasterWeb.Layouts, :app} do
      live "/", CockpitLive
      live "/services", ServiceLive
      live "/services/progress_map", ProgressMapLive
      live "/services/:id/edit", ServiceEditLive
      live "/transaction_types", TransactionTypesLive
      live "/endpoints", EndpointsLive
      live "/validators", ValidatorsLive
      live "/groups", GroupsLive
      live "/reports", ReportsLive
    end
```

- [ ] **Step 2: Delete the PageController files**

```bash
rm lib/ethercoaster_web/controllers/page_controller.ex
rm lib/ethercoaster_web/controllers/page_html.ex
rm -r lib/ethercoaster_web/controllers/page_html/
```

- [ ] **Step 3: Verify it compiles**

Run: `mix compile --force`
Expected: Success, no errors (warnings about module ordering are OK)

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "Add placeholder LiveViews for groups and reports, remove PageController"
```

---

## Chunk 2: CockpitLive Implementation

### Task 4: Create CockpitLive with summary data

**Files:**
- Create: `lib/ethercoaster_web/live/cockpit_live.ex`

The cockpit queries these existing functions on mount:
- `Ethercoaster.Services.list_services()` — returns list of services with a `status` field (values: `"stopped"`, `"completed"`, `"modified"`)
- `Ethercoaster.Endpoints.list_endpoints()` — returns list of endpoint records
- `Ethercoaster.Validators.list_validators()` — returns list of validators preloaded with `:state` (a `ValidatorState` with a `name` field like `"active_ongoing"`, `"pending_queued"`, etc.)
- `Ethercoaster.Validators.list_groups()` — returns list of groups

- [ ] **Step 1: Create the CockpitLive module**

```elixir
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
          <p class="text-sm opacity-70">More coming soon</p>
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
```

- [ ] **Step 2: Verify it compiles and the server starts**

Run: `mix compile --force`
Expected: Success

- [ ] **Step 3: Manual verification**

Visit `http://localhost:4000/` in the browser. Verify:
- 5 cards render in a 3-column grid on wide screens
- Grid collapses to 2 columns, then 1 column as window narrows
- Each card is clickable and navigates to its page
- Breadcrumbs show "Home" on the cockpit page
- Services card shows count and status badges
- Validators card shows count and state badges
- Groups card shows count and "More coming soon"
- Financial Report card shows "Coming soon"

- [ ] **Step 4: Commit**

```bash
git add lib/ethercoaster_web/live/cockpit_live.ex
git commit -m "Add cockpit dashboard with summary cards for all top-level pages"
```

### Task 5: Handle breadcrumbs for root path

**Files:**
- Modify: `lib/ethercoaster_web/components/layouts.ex`

The breadcrumbs component currently renders "Home" for `/`, but since the cockpit IS the home page, it should show just "Home" with no link (or no breadcrumb at all). Check current behavior: when `@current_path` is `"/"`, the breadcrumbs will show just "Home" as a link. Since we're already on the home page, the "Home" link should not be a clickable link.

- [ ] **Step 1: Update breadcrumbs to handle root path**

In `lib/ethercoaster_web/components/layouts.ex`, update the breadcrumbs component template to show "Home" as plain text (not a link) when there are no further path segments:

Replace the existing `~H` template in the `breadcrumbs/1` function with:

```heex
    ~H"""
    <nav class="breadcrumbs px-4 sm:px-6 lg:px-8 text-sm">
      <ul>
        <li :if={@crumbs != []}>
          <a href="/">Home</a>
        </li>
        <li :for={crumb <- @crumbs}>
          <a href={crumb.href}>{crumb.label}</a>
        </li>
      </ul>
    </nav>
    """
```

This hides breadcrumbs entirely on the root path (no crumbs = nothing shown) and only shows "Home >" when navigating into sub-pages.

- [ ] **Step 2: Verify it compiles**

Run: `mix compile`
Expected: Success

- [ ] **Step 3: Commit**

```bash
git add lib/ethercoaster_web/components/layouts.ex
git commit -m "Hide breadcrumbs on cockpit root page"
```
