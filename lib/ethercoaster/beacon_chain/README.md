# Ethercoaster.BeaconChain

Elixir client for the [Ethereum Beacon Chain REST API](https://ethereum.github.io/beacon-APIs/) (consensus layer).

## Configuration

```elixir
config :ethercoaster, Ethercoaster.BeaconChain,
  base_url: "http://localhost:5052",
  api_key: nil,
  receive_timeout: 15_000,
  req_options: [],
  events_enabled: false,
  events_topics: ["head", "block", "attestation", "finalized_checkpoint"]
```

| Key                | Type      | Default                    | Description                                  |
|--------------------|-----------|----------------------------|----------------------------------------------|
| `:base_url`        | string    | `"http://localhost:5052"`  | Beacon node URL                              |
| `:api_key`         | string    | `nil`                      | Bearer token for authenticated endpoints     |
| `:receive_timeout` | integer   | `15_000`                   | HTTP receive timeout (ms)                    |
| `:req_options`     | keyword   | `[]`                       | Extra options forwarded to `Req.new/1`       |
| `:events_enabled`  | boolean   | `false`                    | Start the SSE event listener on boot         |
| `:events_topics`   | list      | `["head", "block", ...]`  | Topics the listener subscribes to            |

Environment variables (`config/runtime.exs`):

- `BEACON_API_URL` — overrides `:base_url`
- `BEACON_API_KEY` — sets `:api_key`
- `BEACON_API_TIMEOUT` — overrides `:receive_timeout`

## Modules

### `Ethercoaster.BeaconChain.Client`

Shared HTTP client built on Req. All endpoint modules delegate to this.

- `new/0` — builds a `Req.Request` from application config
- `get/2` — GET request, returns `{:ok, data} | {:error, %Error{}}`
- `post/3` — POST request with JSON body, same return type

The `"data"` key is automatically extracted from response bodies (standard Beacon API wrapper).

### `Ethercoaster.BeaconChain.Error`

Exception struct with fields `:status`, `:code`, `:message`. Works with both `{:error, %Error{}}` tuples and `raise`.

### `Ethercoaster.BeaconChain.Node`

`/eth/v1/node/*` — node identity, peers, health.

| Function           | Arity | Endpoint                        |
|--------------------|-------|---------------------------------|
| `get_identity/0`   | 0     | `GET /eth/v1/node/identity`     |
| `get_peers/1`      | 0..1  | `GET /eth/v1/node/peers`        |
| `get_peer/1`       | 1     | `GET /eth/v1/node/peers/:id`    |
| `get_peer_count/0` | 0     | `GET /eth/v1/node/peer_count`   |
| `get_version/0`    | 0     | `GET /eth/v1/node/version`      |
| `get_syncing/0`    | 0     | `GET /eth/v1/node/syncing`      |
| `get_health/0`     | 0     | `GET /eth/v1/node/health`       |

`get_health/0` returns `{:ok, status_code}` (200 or 206) instead of body data.

### `Ethercoaster.BeaconChain.Config`

`/eth/v1/config/*` — chain spec and fork info.

| Function                | Arity | Endpoint                              |
|-------------------------|-------|---------------------------------------|
| `get_spec/0`            | 0     | `GET /eth/v1/config/spec`             |
| `get_fork_schedule/0`   | 0     | `GET /eth/v1/config/fork_schedule`    |
| `get_deposit_contract/0`| 0     | `GET /eth/v1/config/deposit_contract` |

### `Ethercoaster.BeaconChain.Beacon`

`/eth/v{1,2}/beacon/*` — the largest module, covering genesis, state, validators, blocks, blobs, pool operations, and rewards.

#### Genesis & State

| Function                     | Arity | Endpoint                                              |
|------------------------------|-------|-------------------------------------------------------|
| `get_genesis/0`              | 0     | `GET /eth/v1/beacon/genesis`                          |
| `get_state_root/1`           | 1     | `GET /eth/v1/beacon/states/:state_id/root`            |
| `get_state_fork/1`           | 1     | `GET /eth/v1/beacon/states/:state_id/fork`            |
| `get_finality_checkpoints/1` | 1     | `GET /eth/v1/beacon/states/:state_id/finality_checkpoints` |

#### Validators

| Function                    | Arity | Endpoint                                                       |
|-----------------------------|-------|----------------------------------------------------------------|
| `get_validators/2`          | 1..2  | `GET /eth/v1/beacon/states/:state_id/validators`               |
| `get_validator/2`           | 2     | `GET /eth/v1/beacon/states/:state_id/validators/:validator_id` |
| `get_validator_balances/2`  | 1..2  | `GET /eth/v1/beacon/states/:state_id/validator_balances`       |

#### Committees & Headers

| Function            | Arity | Endpoint                                             |
|---------------------|-------|------------------------------------------------------|
| `get_committees/2`  | 1..2  | `GET /eth/v1/beacon/states/:state_id/committees`     |
| `get_headers/1`     | 0..1  | `GET /eth/v1/beacon/headers`                         |
| `get_header/1`      | 1     | `GET /eth/v1/beacon/headers/:block_id`               |

#### Blocks & Blobs

| Function                   | Arity | Endpoint                                         |
|----------------------------|-------|--------------------------------------------------|
| `get_block/1`              | 1     | `GET /eth/v2/beacon/blocks/:block_id`            |
| `get_block_root/1`         | 1     | `GET /eth/v1/beacon/blocks/:block_id/root`       |
| `get_block_attestations/1` | 1     | `GET /eth/v1/beacon/blocks/:block_id/attestations` |
| `get_blobs/1`              | 1     | `GET /eth/v1/beacon/blob_sidecars/:block_id`     |

#### Pool (reads)

| Function                        | Arity | Endpoint                                      |
|---------------------------------|-------|-----------------------------------------------|
| `get_pool_attestations/1`       | 0..1  | `GET /eth/v1/beacon/pool/attestations`        |
| `get_pool_attester_slashings/0` | 0     | `GET /eth/v1/beacon/pool/attester_slashings`  |
| `get_pool_proposer_slashings/0` | 0     | `GET /eth/v1/beacon/pool/proposer_slashings`  |
| `get_pool_voluntary_exits/0`    | 0     | `GET /eth/v1/beacon/pool/voluntary_exits`     |
| `get_pool_sync_committees/0`    | 0     | `GET /eth/v1/beacon/pool/sync_committees`     |

#### Pool (writes)

| Function                          | Arity | Endpoint                                       |
|-----------------------------------|-------|-------------------------------------------------|
| `submit_pool_attestations/1`      | 1     | `POST /eth/v1/beacon/pool/attestations`        |
| `submit_pool_attester_slashing/1` | 1     | `POST /eth/v1/beacon/pool/attester_slashings`  |
| `submit_pool_proposer_slashing/1` | 1     | `POST /eth/v1/beacon/pool/proposer_slashings`  |
| `submit_pool_voluntary_exit/1`    | 1     | `POST /eth/v1/beacon/pool/voluntary_exits`     |
| `submit_pool_sync_committees/1`   | 1     | `POST /eth/v1/beacon/pool/sync_committees`     |

#### Rewards

| Function                        | Arity | Endpoint                                                |
|---------------------------------|-------|---------------------------------------------------------|
| `get_sync_committee_rewards/2`  | 1..2  | `POST /eth/v1/beacon/rewards/sync_committee/:block_id` |
| `get_attestation_rewards/2`     | 1..2  | `POST /eth/v1/beacon/rewards/attestations/:epoch`      |

### `Ethercoaster.BeaconChain.Debug`

`/eth/v{1,2}/debug/*` — full state dumps and fork choice.

| Function            | Arity | Endpoint                                      |
|---------------------|-------|-----------------------------------------------|
| `get_state/1`       | 1     | `GET /eth/v2/debug/beacon/states/:state_id`   |
| `get_heads/0`       | 0     | `GET /eth/v2/debug/beacon/heads`              |
| `get_fork_choice/0` | 0     | `GET /eth/v1/debug/fork_choice`               |

### `Ethercoaster.BeaconChain.Validator`

`/eth/v{1,2,3}/validator/*` — duties, block production, attestations, subscriptions.

#### Duties

| Function                 | Arity | Endpoint                                       |
|--------------------------|-------|-------------------------------------------------|
| `get_attester_duties/2`  | 2     | `POST /eth/v1/validator/duties/attester/:epoch` |
| `get_proposer_duties/1`  | 1     | `GET /eth/v1/validator/duties/proposer/:epoch`  |
| `get_sync_duties/2`      | 2     | `POST /eth/v1/validator/duties/sync/:epoch`     |

#### Block Production

| Function                  | Arity | Endpoint                                        |
|---------------------------|-------|-------------------------------------------------|
| `produce_block/2`         | 1..2  | `GET /eth/v3/validator/blocks/:slot`            |
| `produce_blinded_block/2` | 1..2  | `GET /eth/v1/validator/blinded_blocks/:slot`    |

#### Attestation

| Function                          | Arity | Endpoint                                           |
|-----------------------------------|-------|-----------------------------------------------------|
| `get_attestation_data/1`          | 1     | `GET /eth/v1/validator/attestation_data`            |
| `get_aggregate_attestation/1`     | 1     | `GET /eth/v1/validator/aggregate_attestation`       |
| `submit_aggregate_and_proofs/1`   | 1     | `POST /eth/v1/validator/aggregate_and_proofs`       |

#### Subscriptions & Proposer

| Function                                  | Arity | Endpoint                                                   |
|-------------------------------------------|-------|-------------------------------------------------------------|
| `submit_beacon_committee_subscriptions/1` | 1     | `POST /eth/v1/validator/beacon_committee_subscriptions`    |
| `submit_sync_committee_subscriptions/1`   | 1     | `POST /eth/v1/validator/sync_committee_subscriptions`      |
| `prepare_beacon_proposer/1`               | 1     | `POST /eth/v1/validator/prepare_beacon_proposer`           |
| `register_validator/1`                    | 1     | `POST /eth/v1/validator/register_validator`                |

#### Liveness

| Function          | Arity | Endpoint                                      |
|-------------------|-------|-----------------------------------------------|
| `get_liveness/2`  | 2     | `POST /eth/v1/validator/liveness/:epoch`      |

### `Ethercoaster.BeaconChain.Events`

PubSub wrapper for SSE event distribution.

| Function         | Arity | Description                                      |
|------------------|-------|--------------------------------------------------|
| `subscribe/1`    | 1     | Subscribe calling process to a topic             |
| `unsubscribe/1`  | 1     | Unsubscribe calling process from a topic         |
| `broadcast/2`    | 2     | Broadcast `{:beacon_event, topic, data}` message |

Topics are prefixed with `"beacon_chain:events:"` internally.

### `Ethercoaster.BeaconChain.Events.Listener`

GenServer that maintains a long-lived SSE connection using `Req.get` with `into: :self`. Parses the SSE text protocol (`event:` / `data:` lines), decodes JSON payloads, and broadcasts via `Events.broadcast/2`. Reconnects automatically with exponential backoff (1s initial, 30s max).

## Usage Examples

```elixir
# Get node version
{:ok, version} = Ethercoaster.BeaconChain.Node.get_version()

# Get current head block
{:ok, block} = Ethercoaster.BeaconChain.Beacon.get_block("head")

# Get validators at head state
{:ok, validators} = Ethercoaster.BeaconChain.Beacon.get_validators("head", status: "active")

# Get chain spec
{:ok, spec} = Ethercoaster.BeaconChain.Config.get_spec()

# Subscribe to head events (requires events_enabled: true)
Ethercoaster.BeaconChain.Events.subscribe("head")
# Receive: {:beacon_event, "head", %{"slot" => "12345", ...}}
```
