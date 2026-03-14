defmodule Ethercoaster.ExecutionChain do
  @moduledoc """
  Ethereum execution layer (EL) JSON-RPC client.

  ## Configuration

      config :ethercoaster, Ethercoaster.ExecutionChain,
        base_url: "http://localhost:8545",
        ws_url: "ws://localhost:8546",
        receive_timeout: 15_000,
        req_options: []

  ## Submodules

    * `Ethercoaster.ExecutionChain.Client` — shared HTTP JSON-RPC client
    * `Ethercoaster.ExecutionChain.Eth` — `eth_*` namespace RPC methods
    * `Ethercoaster.ExecutionChain.Block` — block reward and fee recipient helpers
    * `Ethercoaster.ExecutionChain.WebSocket` — WebSocket JSON-RPC client
  """
end
