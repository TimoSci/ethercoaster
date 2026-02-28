defmodule Ethercoaster.ValidatorsTest do
  use ExUnit.Case, async: true

  alias Ethercoaster.BeaconChain.Client
  alias Ethercoaster.Validators

  @pubkey "0x" <> String.duplicate("ab", 48)

  defp stub_validator(index) do
    fn conn ->
      if conn.request_path =~ "/validators/" do
        Req.Test.json(conn, %{
          "data" => %{
            "index" => index,
            "status" => "active_ongoing",
            "validator" => %{"pubkey" => @pubkey}
          }
        })
      else
        # pass through to next handler
        conn
      end
    end
  end

  defp stub_syncing(head_slot) do
    fn conn ->
      if conn.request_path == "/eth/v1/node/syncing" do
        Req.Test.json(conn, %{
          "data" => %{
            "head_slot" => head_slot,
            "sync_distance" => "0",
            "is_syncing" => false
          }
        })
      else
        conn
      end
    end
  end

  defp stub_attestation_rewards(validator_index) do
    fn conn ->
      if conn.request_path =~ "/rewards/attestations/" do
        Req.Test.json(conn, %{
          "data" => %{
            "total_rewards" => [
              %{
                "validator_index" => validator_index,
                "head" => "2000",
                "target" => "5000",
                "source" => "3000",
                "inactivity" => "0"
              }
            ]
          }
        })
      else
        conn
      end
    end
  end

  defp stub_all(opts) do
    head_slot = Keyword.get(opts, :head_slot, "3200")
    validator_index = Keyword.get(opts, :validator_index, "42")

    validator_stub = stub_validator(validator_index)
    syncing_stub = stub_syncing(head_slot)
    rewards_stub = stub_attestation_rewards(validator_index)

    Req.Test.stub(Client, fn conn ->
      conn
      |> validator_stub.()
      |> then(fn
        %Plug.Conn{state: :sent} = conn -> conn
        conn -> syncing_stub.(conn)
      end)
      |> then(fn
        %Plug.Conn{state: :sent} = conn -> conn
        conn -> rewards_stub.(conn)
      end)
    end)
  end

  describe "query_rewards/2 happy path" do
    test "returns rewards for a valid validator" do
      stub_all(head_slot: "3200")

      assert {:ok, result} = Validators.query_rewards(@pubkey, 3200)
      assert result.pubkey == @pubkey
      assert result.validator_index == 42
      assert result.from_epoch >= 0
      assert result.to_epoch == 99
      assert length(result.epoch_rewards) > 0

      reward = hd(result.epoch_rewards)
      assert reward.head == 2000
      assert reward.target == 5000
      assert reward.source == 3000
      assert reward.inactivity == 0
      assert reward.total == 10000
    end
  end

  describe "query_rewards/2 validator not found" do
    test "returns error when validator does not exist" do
      Req.Test.stub(Client, fn conn ->
        if conn.request_path =~ "/validators/" do
          conn
          |> Plug.Conn.put_status(404)
          |> Req.Test.json(%{"code" => 404, "message" => "Validator not found"})
        else
          Req.Test.json(conn, %{"data" => %{}})
        end
      end)

      assert {:error, message} = Validators.query_rewards(@pubkey, 100)
      assert message =~ "Validator not found"
    end
  end

  describe "query_rewards/2 node unreachable" do
    test "returns error when syncing endpoint fails" do
      Req.Test.stub(Client, fn conn ->
        if conn.request_path =~ "/validators/" do
          Req.Test.json(conn, %{
            "data" => %{"index" => "42", "status" => "active_ongoing"}
          })
        else
          conn
          |> Plug.Conn.put_status(500)
          |> Req.Test.json(%{"code" => 500, "message" => "Internal error"})
        end
      end)

      assert {:error, message} = Validators.query_rewards(@pubkey, 100)
      assert message =~ "beacon node"
    end
  end

  describe "query_rewards/2 partial failures" do
    test "returns successful epochs when some fail" do
      Req.Test.stub(Client, fn conn ->
        cond do
          conn.request_path =~ "/validators/" ->
            Req.Test.json(conn, %{
              "data" => %{"index" => "42", "status" => "active_ongoing"}
            })

          conn.request_path == "/eth/v1/node/syncing" ->
            Req.Test.json(conn, %{
              "data" => %{"head_slot" => "128", "sync_distance" => "0", "is_syncing" => false}
            })

          conn.request_path =~ "/rewards/attestations/0" ->
            conn
            |> Plug.Conn.put_status(500)
            |> Req.Test.json(%{"code" => 500, "message" => "error"})

          conn.request_path =~ "/rewards/attestations/" ->
            Req.Test.json(conn, %{
              "data" => %{
                "total_rewards" => [
                  %{
                    "validator_index" => "42",
                    "head" => "1000",
                    "target" => "2000",
                    "source" => "1500",
                    "inactivity" => "0"
                  }
                ]
              }
            })
        end
      end)

      assert {:ok, result} = Validators.query_rewards(@pubkey, 128)
      # Epoch 0 failed, but others should succeed
      assert result.epoch_count >= 1
    end
  end
end
