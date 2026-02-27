defmodule Ethercoaster.BeaconChain.Debug do
  @moduledoc """
  Beacon Chain `/eth/v{1,2}/debug/*` endpoints.
  """

  alias Ethercoaster.BeaconChain.Client

  @doc "Returns the full beacon state for the given `state_id`."
  def get_state(state_id), do: Client.get("/eth/v2/debug/beacon/states/#{state_id}")

  @doc "Returns the fork choice heads."
  def get_heads, do: Client.get("/eth/v2/debug/beacon/heads")

  @doc "Returns the full fork choice store."
  def get_fork_choice, do: Client.get("/eth/v1/debug/fork_choice")
end
