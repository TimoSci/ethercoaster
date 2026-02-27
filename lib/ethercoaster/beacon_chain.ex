defmodule Ethercoaster.BeaconChain do
  @moduledoc """
  Ethereum Beacon Chain (consensus layer) REST API client.

  ## Configuration

      config :ethercoaster, Ethercoaster.BeaconChain,
        base_url: "http://localhost:5052",
        api_key: nil,
        receive_timeout: 15_000,
        req_options: [],
        events_enabled: false,
        events_topics: ["head", "block", "attestation", "finalized_checkpoint"]

  ## Submodules

    * `Ethercoaster.BeaconChain.Client` — shared HTTP client
    * `Ethercoaster.BeaconChain.Beacon` — `/eth/v{1,2}/beacon/*` endpoints
    * `Ethercoaster.BeaconChain.Config` — `/eth/v1/config/*` endpoints
    * `Ethercoaster.BeaconChain.Debug` — `/eth/v{1,2}/debug/*` endpoints
    * `Ethercoaster.BeaconChain.Node` — `/eth/v1/node/*` endpoints
    * `Ethercoaster.BeaconChain.Validator` — `/eth/v{1,2,3}/validator/*` endpoints
    * `Ethercoaster.BeaconChain.Events` — PubSub interface for SSE events
    * `Ethercoaster.BeaconChain.Events.Listener` — GenServer maintaining SSE connection
  """
end
