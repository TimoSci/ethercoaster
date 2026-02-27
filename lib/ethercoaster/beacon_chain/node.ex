defmodule Ethercoaster.BeaconChain.Node do
  @moduledoc """
  Beacon Chain `/eth/v1/node/*` endpoints.
  """

  alias Ethercoaster.BeaconChain.Client

  @doc "Returns the node's network identity."
  def get_identity, do: Client.get("/eth/v1/node/identity")

  @doc "Returns the node's connected peers, optionally filtered by `params`."
  def get_peers(params \\ []), do: Client.get("/eth/v1/node/peers", params)

  @doc "Returns details about a specific peer by `peer_id`."
  def get_peer(peer_id), do: Client.get("/eth/v1/node/peers/#{peer_id}")

  @doc "Returns the node's peer count summary."
  def get_peer_count, do: Client.get("/eth/v1/node/peer_count")

  @doc "Returns the node's software version."
  def get_version, do: Client.get("/eth/v1/node/version")

  @doc "Returns the node's sync status."
  def get_syncing, do: Client.get("/eth/v1/node/syncing")

  @doc """
  Returns the node's health status.

  Returns `{:ok, status_code}` on success (200 or 206) or `{:error, %Error{}}`.
  """
  def get_health do
    case Req.get(Client.new(), url: "/eth/v1/node/health") do
      {:ok, %Req.Response{status: status}} when status in [200, 206] ->
        {:ok, status}

      {:ok, %Req.Response{status: status, body: body}} when is_map(body) ->
        {:error,
         %Ethercoaster.BeaconChain.Error{
           status: status,
           code: body["code"],
           message: body["message"] || "HTTP #{status}"
         }}

      {:ok, %Req.Response{status: status}} ->
        {:error, %Ethercoaster.BeaconChain.Error{status: status, message: "HTTP #{status}"}}

      {:error, exception} ->
        {:error,
         %Ethercoaster.BeaconChain.Error{
           message: "request failed: #{Exception.message(exception)}"
         }}
    end
  end
end
