defmodule Ethercoaster.BeaconChain.Events do
  @moduledoc """
  PubSub interface for Beacon Chain SSE events.

  Subscribe to event topics to receive `{:beacon_event, topic, data}` messages
  broadcast by the `Ethercoaster.BeaconChain.Events.Listener`.

  ## Topics

  Supported topics match the Beacon API event stream topics:
  `"head"`, `"block"`, `"attestation"`, `"voluntary_exit"`,
  `"finalized_checkpoint"`, `"chain_reorg"`, etc.
  """

  @pubsub Ethercoaster.PubSub
  @prefix "beacon_chain:events:"

  @doc "Subscribes the calling process to the given event `topic`."
  def subscribe(topic) do
    Phoenix.PubSub.subscribe(@pubsub, @prefix <> topic)
  end

  @doc "Unsubscribes the calling process from the given event `topic`."
  def unsubscribe(topic) do
    Phoenix.PubSub.unsubscribe(@pubsub, @prefix <> topic)
  end

  @doc """
  Broadcasts an event to all subscribers of the given `topic`.

  Called internally by the Listener. Sends `{:beacon_event, topic, data}` to subscribers.
  """
  def broadcast(topic, data) do
    Phoenix.PubSub.broadcast(@pubsub, @prefix <> topic, {:beacon_event, topic, data})
  end
end
