# Cockpit Page Design

## Overview

Replace the Phoenix welcome page at `/` with a LiveView cockpit dashboard. The cockpit shows 5 summary cards in a responsive grid, each linking to its respective page.

## Layout

- 3 columns on large screens, 2 on medium, 1 on small
- Each card is a clickable `<a>` tag linking to its page
- Uses DaisyUI card styling consistent with the rest of the app
- Style: richer detail cards with status badges, counts, and secondary info

## Cards

| Card | Route | Data |
|------|-------|------|
| Services | `/services` | Total count, status breakdown (running/paused/stopped) |
| Endpoints | `/endpoints` | Total count, health status breakdown (healthy/unreachable) |
| Validators | `/validators` | Total count, state breakdown badges (active/pending/exited) |
| Groups | `/groups` | Total group count, "more coming soon" subtitle |
| Financial Report | `/reports` | Placeholder, "coming soon" |

All data is static — loaded on mount, no live updates.

## Implementation Changes

1. **New `CockpitLive`** LiveView at `/` — queries Services, Endpoints, Validators contexts for summary data on mount
2. **New `GroupsLive`** placeholder LiveView at `/groups`
3. **New `ReportsLive`** placeholder LiveView at `/reports`
4. **Remove `PageController`** and its templates (`page_controller.ex`, `page_html.ex`, `page_html/home.html.heex`) — no longer needed
5. **Update router** — replace `get "/", PageController, :home` with `live "/", CockpitLive` inside the existing `live_session`; add `/groups` and `/reports` routes
6. All new routes go inside the existing `live_session :default` so they inherit the app layout and breadcrumbs
