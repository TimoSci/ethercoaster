defmodule Ethercoaster.BeaconChain.DebugTest do
  use ExUnit.Case, async: true

  alias Ethercoaster.BeaconChain.{Client, Debug}

  describe "get_state/1" do
    test "returns the full beacon state" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v2/debug/beacon/states/head"
        assert conn.method == "GET"
        Req.Test.json(conn, %{"data" => %{"slot" => "12345", "validators" => []}})
      end)

      assert {:ok, %{"slot" => "12345"}} = Debug.get_state("head")
    end

    test "accepts numeric state_id" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v2/debug/beacon/states/100"
        Req.Test.json(conn, %{"data" => %{"slot" => "100"}})
      end)

      assert {:ok, %{"slot" => "100"}} = Debug.get_state(100)
    end
  end

  describe "get_heads/0" do
    test "returns fork choice heads" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v2/debug/beacon/heads"

        Req.Test.json(conn, %{
          "data" => [
            %{"slot" => "12345", "root" => "0xabc", "execution_optimistic" => false}
          ]
        })
      end)

      assert {:ok, [%{"slot" => "12345", "root" => "0xabc"}]} = Debug.get_heads()
    end
  end

  describe "get_fork_choice/0" do
    test "returns the fork choice store" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/debug/fork_choice"

        Req.Test.json(conn, %{
          "data" => %{
            "justified_checkpoint" => %{"epoch" => "100", "root" => "0x1"},
            "finalized_checkpoint" => %{"epoch" => "99", "root" => "0x2"},
            "fork_choice_nodes" => []
          }
        })
      end)

      assert {:ok, %{"justified_checkpoint" => %{"epoch" => "100"}}} = Debug.get_fork_choice()
    end
  end
end
