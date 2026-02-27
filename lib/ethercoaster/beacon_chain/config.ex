defmodule Ethercoaster.BeaconChain.Config do
  @moduledoc """
  Beacon Chain `/eth/v1/config/*` endpoints.
  """

  alias Ethercoaster.BeaconChain.Client

  @doc "Returns the full spec configuration."
  def get_spec, do: Client.get("/eth/v1/config/spec")

  @doc "Returns the fork schedule."
  def get_fork_schedule, do: Client.get("/eth/v1/config/fork_schedule")

  @doc "Returns the deposit contract address and chain ID."
  def get_deposit_contract, do: Client.get("/eth/v1/config/deposit_contract")
end
