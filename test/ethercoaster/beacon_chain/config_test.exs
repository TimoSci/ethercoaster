defmodule Ethercoaster.BeaconChain.ConfigTest do
  use ExUnit.Case, async: true

  alias Ethercoaster.BeaconChain.{Client, Config}

  describe "get_spec/0" do
    test "returns the chain spec" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/config/spec"
        assert conn.method == "GET"

        Req.Test.json(conn, %{
          "data" => %{
            "SECONDS_PER_SLOT" => "12",
            "SLOTS_PER_EPOCH" => "32",
            "MAX_VALIDATORS_PER_COMMITTEE" => "2048"
          }
        })
      end)

      assert {:ok, %{"SECONDS_PER_SLOT" => "12"}} = Config.get_spec()
    end
  end

  describe "get_fork_schedule/0" do
    test "returns the fork schedule" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/config/fork_schedule"

        Req.Test.json(conn, %{
          "data" => [
            %{
              "previous_version" => "0x00000000",
              "current_version" => "0x01000000",
              "epoch" => "0"
            }
          ]
        })
      end)

      assert {:ok, [%{"epoch" => "0"} | _]} = Config.get_fork_schedule()
    end
  end

  describe "get_deposit_contract/0" do
    test "returns the deposit contract info" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/config/deposit_contract"

        Req.Test.json(conn, %{
          "data" => %{
            "chain_id" => "1",
            "address" => "0x00000000219ab540356cBB839Cbe05303d7705Fa"
          }
        })
      end)

      assert {:ok, %{"chain_id" => "1", "address" => "0x" <> _}} = Config.get_deposit_contract()
    end
  end
end
