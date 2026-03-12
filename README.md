# Ethercoaster

Ethercoaster is an Ethereum validator management dashboard built with Phoenix LiveView. It provides tools for tracking validators, organizing them into groups and supergroups, monitoring beacon chain state, and managing service endpoints.

## Prerequisites

- Elixir ~> 1.15
- PostgreSQL
- Node.js (for asset building)

## Setup

```bash
mix setup
```

This installs dependencies, creates the database, runs migrations, seeds data, and builds assets.

## Running

```bash
mix phx.server
```

Then visit [`localhost:4000`](http://localhost:4000).

To run inside IEx:

```bash
iex -S mix phx.server
```

## Testing

```bash
mix test
```

## Documentation

Detailed guides will be added to the `guides/` directory.
