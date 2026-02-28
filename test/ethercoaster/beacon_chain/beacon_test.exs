defmodule Ethercoaster.BeaconChain.BeaconTest do
  use ExUnit.Case, async: true

  alias Ethercoaster.BeaconChain.{Beacon, Client}

  # Genesis

  describe "get_genesis/0" do
    test "returns genesis info" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/beacon/genesis"

        Req.Test.json(conn, %{
          "data" => %{
            "genesis_time" => "1606824023",
            "genesis_validators_root" => "0x4b363db94e286120d76eb905340fdd4e54bfe9f06bf33ff6cf5ad27f511bfe95",
            "genesis_fork_version" => "0x00000000"
          }
        })
      end)

      assert {:ok, %{"genesis_time" => "1606824023"}} = Beacon.get_genesis()
    end
  end

  # State

  describe "get_state_root/1" do
    test "returns state root for a given state_id" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/beacon/states/head/root"
        Req.Test.json(conn, %{"data" => %{"root" => "0xabcd"}})
      end)

      assert {:ok, %{"root" => "0xabcd"}} = Beacon.get_state_root("head")
    end
  end

  describe "get_state_fork/1" do
    test "returns fork data" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/beacon/states/head/fork"

        Req.Test.json(conn, %{
          "data" => %{
            "previous_version" => "0x00000000",
            "current_version" => "0x04000000",
            "epoch" => "0"
          }
        })
      end)

      assert {:ok, %{"current_version" => "0x04000000"}} = Beacon.get_state_fork("head")
    end
  end

  describe "get_finality_checkpoints/1" do
    test "returns finality checkpoints" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/beacon/states/head/finality_checkpoints"

        Req.Test.json(conn, %{
          "data" => %{
            "previous_justified" => %{"epoch" => "100", "root" => "0x1"},
            "current_justified" => %{"epoch" => "101", "root" => "0x2"},
            "finalized" => %{"epoch" => "100", "root" => "0x3"}
          }
        })
      end)

      assert {:ok, %{"finalized" => %{"epoch" => "100"}}} =
               Beacon.get_finality_checkpoints("head")
    end
  end

  # Validators

  describe "get_validators/2" do
    test "returns validators at a state" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/beacon/states/head/validators"

        Req.Test.json(conn, %{
          "data" => [
            %{"index" => "0", "status" => "active_ongoing", "balance" => "32000000000"}
          ]
        })
      end)

      assert {:ok, [%{"index" => "0"}]} = Beacon.get_validators("head")
    end

    test "passes filter params" do
      Req.Test.stub(Client, fn conn ->
        assert conn.query_string =~ "status=active"
        Req.Test.json(conn, %{"data" => []})
      end)

      assert {:ok, []} = Beacon.get_validators("head", status: "active")
    end
  end

  describe "get_validator/2" do
    test "returns a specific validator" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/beacon/states/head/validators/0"
        Req.Test.json(conn, %{"data" => %{"index" => "0", "status" => "active_ongoing"}})
      end)

      assert {:ok, %{"index" => "0"}} = Beacon.get_validator("head", "0")
    end
  end

  describe "get_validator_balances/2" do
    test "returns validator balances" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/beacon/states/head/validator_balances"
        Req.Test.json(conn, %{"data" => [%{"index" => "0", "balance" => "32000000000"}]})
      end)

      assert {:ok, [%{"index" => "0"}]} = Beacon.get_validator_balances("head")
    end
  end

  # Committees

  describe "get_committees/2" do
    test "returns committees" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/beacon/states/head/committees"
        Req.Test.json(conn, %{"data" => [%{"index" => "0", "slot" => "100"}]})
      end)

      assert {:ok, [%{"index" => "0"}]} = Beacon.get_committees("head")
    end

    test "passes filter params" do
      Req.Test.stub(Client, fn conn ->
        assert conn.query_string =~ "epoch=10"
        Req.Test.json(conn, %{"data" => []})
      end)

      assert {:ok, []} = Beacon.get_committees("head", epoch: 10)
    end
  end

  # Headers

  describe "get_headers/1" do
    test "returns block headers" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/beacon/headers"
        Req.Test.json(conn, %{"data" => [%{"root" => "0xabc", "header" => %{}}]})
      end)

      assert {:ok, [%{"root" => "0xabc"}]} = Beacon.get_headers()
    end
  end

  describe "get_header/1" do
    test "returns a specific block header" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/beacon/headers/head"
        Req.Test.json(conn, %{"data" => %{"root" => "0xabc", "canonical" => true}})
      end)

      assert {:ok, %{"root" => "0xabc"}} = Beacon.get_header("head")
    end
  end

  # Blocks

  describe "get_block/1" do
    test "returns a block" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v2/beacon/blocks/head"
        Req.Test.json(conn, %{"data" => %{"message" => %{"slot" => "12345"}}})
      end)

      assert {:ok, %{"message" => %{"slot" => "12345"}}} = Beacon.get_block("head")
    end
  end

  describe "get_block_root/1" do
    test "returns block root" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/beacon/blocks/head/root"
        Req.Test.json(conn, %{"data" => %{"root" => "0xdeadbeef"}})
      end)

      assert {:ok, %{"root" => "0xdeadbeef"}} = Beacon.get_block_root("head")
    end
  end

  describe "get_block_attestations/1" do
    test "returns block attestations" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/beacon/blocks/head/attestations"
        Req.Test.json(conn, %{"data" => [%{"aggregation_bits" => "0x01"}]})
      end)

      assert {:ok, [%{"aggregation_bits" => "0x01"}]} = Beacon.get_block_attestations("head")
    end
  end

  # Blobs

  describe "get_blobs/1" do
    test "returns blob sidecars" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/beacon/blob_sidecars/head"
        Req.Test.json(conn, %{"data" => [%{"index" => "0", "blob" => "0x00"}]})
      end)

      assert {:ok, [%{"index" => "0"}]} = Beacon.get_blobs("head")
    end
  end

  # Pool reads

  describe "get_pool_attestations/1" do
    test "returns pool attestations" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/beacon/pool/attestations"
        Req.Test.json(conn, %{"data" => []})
      end)

      assert {:ok, []} = Beacon.get_pool_attestations()
    end
  end

  describe "get_pool_attester_slashings/0" do
    test "returns attester slashings" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/beacon/pool/attester_slashings"
        Req.Test.json(conn, %{"data" => []})
      end)

      assert {:ok, []} = Beacon.get_pool_attester_slashings()
    end
  end

  describe "get_pool_proposer_slashings/0" do
    test "returns proposer slashings" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/beacon/pool/proposer_slashings"
        Req.Test.json(conn, %{"data" => []})
      end)

      assert {:ok, []} = Beacon.get_pool_proposer_slashings()
    end
  end

  describe "get_pool_voluntary_exits/0" do
    test "returns voluntary exits" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/beacon/pool/voluntary_exits"
        Req.Test.json(conn, %{"data" => []})
      end)

      assert {:ok, []} = Beacon.get_pool_voluntary_exits()
    end
  end

  describe "get_pool_sync_committees/0" do
    test "returns sync committee messages" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/beacon/pool/sync_committees"
        Req.Test.json(conn, %{"data" => []})
      end)

      assert {:ok, []} = Beacon.get_pool_sync_committees()
    end
  end

  # Pool writes

  describe "submit_pool_attestations/1" do
    test "submits attestations" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/beacon/pool/attestations"
        assert conn.method == "POST"
        Req.Test.json(conn, %{"data" => nil})
      end)

      assert {:ok, _} = Beacon.submit_pool_attestations([%{"aggregation_bits" => "0x01"}])
    end
  end

  describe "submit_pool_attester_slashing/1" do
    test "submits an attester slashing" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/beacon/pool/attester_slashings"
        assert conn.method == "POST"
        Req.Test.json(conn, %{"data" => nil})
      end)

      assert {:ok, _} = Beacon.submit_pool_attester_slashing(%{})
    end
  end

  describe "submit_pool_proposer_slashing/1" do
    test "submits a proposer slashing" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/beacon/pool/proposer_slashings"
        assert conn.method == "POST"
        Req.Test.json(conn, %{"data" => nil})
      end)

      assert {:ok, _} = Beacon.submit_pool_proposer_slashing(%{})
    end
  end

  describe "submit_pool_voluntary_exit/1" do
    test "submits a voluntary exit" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/beacon/pool/voluntary_exits"
        assert conn.method == "POST"
        Req.Test.json(conn, %{"data" => nil})
      end)

      assert {:ok, _} = Beacon.submit_pool_voluntary_exit(%{})
    end
  end

  describe "submit_pool_sync_committees/1" do
    test "submits sync committee messages" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/beacon/pool/sync_committees"
        assert conn.method == "POST"
        Req.Test.json(conn, %{"data" => nil})
      end)

      assert {:ok, _} = Beacon.submit_pool_sync_committees([%{}])
    end
  end

  # Rewards

  describe "get_sync_committee_rewards/2" do
    test "returns sync committee rewards" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/beacon/rewards/sync_committee/head"
        assert conn.method == "POST"
        Req.Test.json(conn, %{"data" => [%{"validator_index" => "0", "reward" => "1000"}]})
      end)

      assert {:ok, [%{"validator_index" => "0"}]} = Beacon.get_sync_committee_rewards("head")
    end
  end

  describe "get_attestation_rewards/2" do
    test "returns attestation rewards" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/beacon/rewards/attestations/100"
        assert conn.method == "POST"
        Req.Test.json(conn, %{"data" => %{"total_rewards" => []}})
      end)

      assert {:ok, %{"total_rewards" => []}} = Beacon.get_attestation_rewards("100")
    end
  end
end
