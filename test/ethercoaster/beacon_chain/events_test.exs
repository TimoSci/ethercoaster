defmodule Ethercoaster.BeaconChain.EventsTest do
  use ExUnit.Case, async: true

  alias Ethercoaster.BeaconChain.Events

  describe "subscribe/1" do
    test "subscribes the calling process to a topic" do
      :ok = Events.subscribe("head")
      Events.broadcast("head", %{"slot" => "12345"})

      assert_receive {:beacon_event, "head", %{"slot" => "12345"}}
    end
  end

  describe "unsubscribe/1" do
    test "unsubscribes the calling process from a topic" do
      :ok = Events.subscribe("block")
      :ok = Events.unsubscribe("block")

      Events.broadcast("block", %{"slot" => "12345"})

      refute_receive {:beacon_event, "block", _}
    end
  end

  describe "broadcast/2" do
    test "sends {:beacon_event, topic, data} to subscribers" do
      :ok = Events.subscribe("finalized_checkpoint")

      Events.broadcast("finalized_checkpoint", %{
        "block" => "0xabc",
        "state" => "0xdef",
        "epoch" => "100"
      })

      assert_receive {:beacon_event, "finalized_checkpoint", %{"epoch" => "100"}}
    end

    test "does not send to unrelated topic subscribers" do
      :ok = Events.subscribe("head")

      Events.broadcast("block", %{"slot" => "100"})

      refute_receive {:beacon_event, _, _}
    end

    test "delivers to multiple subscribers" do
      parent = self()

      :ok = Events.subscribe("chain_reorg")

      task =
        Task.async(fn ->
          :ok = Events.subscribe("chain_reorg")
          send(parent, :subscribed)

          receive do
            {:beacon_event, "chain_reorg", data} -> data
          after
            1000 -> :timeout
          end
        end)

      receive do
        :subscribed -> :ok
      after
        1000 -> flunk("task did not subscribe in time")
      end

      Events.broadcast("chain_reorg", %{"slot" => "500"})

      assert_receive {:beacon_event, "chain_reorg", %{"slot" => "500"}}
      assert %{"slot" => "500"} = Task.await(task)
    end
  end
end
