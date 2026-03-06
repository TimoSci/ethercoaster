# Services Feature Design

## Overview

A "Services" feature that allows users to create persistent background query jobs for fetching validator attestation rewards. Each service is a GenServer that fetches data in batches and saves results to the database. Services can be paused, resumed, and display real-time progress via LiveView.

## Database Schema

### `services` table

| Column | Type | Notes |
|--------|------|-------|
| id | bigint (PK) | auto |
| name | string | optional label |
| categories | array of strings | e.g. `["attestation"]` |
| query_mode | string | "last_n_epochs" or "epoch_range" |
| last_n_epochs | integer | nullable |
| epoch_from | integer | nullable |
| epoch_to | integer | nullable |
| endpoint | string | nullable, custom beacon node URL |
| status | string | "stopped" (default) or "completed" |
| inserted_at / updated_at | timestamps | standard |

### `services_validators` join table

| Column | Type | Notes |
|--------|------|-------|
| service_id | bigint (FK -> services) | cascade on delete |
| validator_id | bigint (FK -> validators) | cascade on delete |
| primary key | composite (service_id, validator_id) | |

Runtime states ("running", "paused") are tracked by the GenServer in memory. On application restart, all services revert to their DB status ("stopped" or "completed").

## Architecture

### Supervision Tree Additions

- `Ethercoaster.ServiceRegistry` - Registry for looking up running workers
- `Ethercoaster.ServiceManager` - DynamicSupervisor for service workers

### `Ethercoaster.Service.Worker` (GenServer)

One GenServer per active service. State:

```elixir
%{
  service_id: integer,
  status: :running | :paused,
  validators: [%{pubkey: string, index: integer}],
  work_queue: [{validator, epoch, category}],
  epochs_completed: integer,
  epochs_total: integer,
  current_batch: reference | nil,
  log: [string]  # capped at last 50 entries
}
```

### Lifecycle

1. User presses "play" -> LiveView calls `ServiceManager.start_service(service_id)`
2. ServiceManager starts a Worker under DynamicSupervisor, registered via `ServiceRegistry`
3. Worker loads config from DB, resolves epoch list, checks cache for already-fetched epochs
4. Worker fetches in batches of 50 epochs, all validators in parallel per batch
5. After each batch: stores results via Cache, broadcasts progress via PubSub
6. User presses "pause" -> Worker finishes current batch, then stops
7. On completion -> updates DB status to "completed", stops worker
8. On resume -> recalculates remaining epochs (checks cache), continues

### PubSub

Topic: `"service:#{service_id}"`
Events: `{:progress, map}`, `{:log, message}`, `{:status_change, status}`

## Query Execution Logic

### Epoch Resolution

- `"last_n_epochs"` -> fetch head slot from beacon API, calculate epoch range
- `"epoch_range"` -> use epoch_from/epoch_to directly

### Work Queue Building

For each validator x category combination:
1. Check cached epochs via `Cache.get_cached_epoch_set/4`
2. Build `{validator, epoch, category}` tuples for uncached epochs
3. Set epochs_total = full count, epochs_completed = total - queue size

### Batch Processing

1. Take next 50 epochs from work queue
2. Group by {validator, category}, process all validators in parallel
3. Dispatch to appropriate fetch function per category:
   - `:attestation` -> existing attestation fetch logic
   - `:sync_committee` -> no-op (future)
   - `:block_proposal` -> no-op (future)
4. Store results via `Cache.store_and_mark/5`
5. Broadcast progress + log via PubSub
6. If paused -> stop; else -> next batch
7. When queue empty -> mark "completed" in DB, stop worker

### Error Handling

- Failed batches are logged, skipped, and can be retried on resume (not in cache)
- Custom endpoint: builds separate Req client if service has endpoint override

## LiveView UI

### Route

`GET /services` -> `EthercoasterWeb.ServiceLive`

### Create Service Card (top)

- **Validators**: Dynamic list of text fields (pubkey or index) with Add/Remove buttons. File upload for CSV/JSON that populates the list.
- **Categories**: Checkboxes. Only "Attestation" enabled; others disabled with "coming soon".
- **Last N Epochs**: Number input
- **Epoch From / To**: Number inputs
- **Date From / To**: Date inputs (converted to epochs on submit, converted back for display)
- **Endpoint**: Optional text input
- **Name**: Optional text input
- **"Save Service" button**

### Service Cards Stack (bottom)

Each card shows:
- Name (or "Service #N")
- Validator count and epoch range summary
- Category list with status indicators (checkmark, spinner, dash)
- Status badge: Stopped / Running / Paused / Completed
- Play button (when stopped/paused)
- Pause button (when running)
- Delete button
- Progress bar with epoch count and percentage
- Scrollable log panel with recent activity

### Real-time Updates

LiveView subscribes to PubSub topics for all services. Worker broadcasts trigger `handle_info` to update progress/logs. On mount, checks Registry for running workers to determine runtime status.
