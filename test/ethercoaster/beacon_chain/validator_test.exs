defmodule Ethercoaster.BeaconChain.ValidatorTest do
  use ExUnit.Case, async: true

  alias Ethercoaster.BeaconChain.{Client, Validator}

  # Duties

  describe "get_attester_duties/2" do
    test "posts validator indices and returns duties" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/validator/duties/attester/100"
        assert conn.method == "POST"
        Req.Test.json(conn, %{"data" => [%{"validator_index" => "0", "slot" => "3200"}]})
      end)

      assert {:ok, [%{"validator_index" => "0"}]} = Validator.get_attester_duties(100, ["0"])
    end
  end

  describe "get_proposer_duties/1" do
    test "returns proposer duties for an epoch" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/validator/duties/proposer/100"
        assert conn.method == "GET"
        Req.Test.json(conn, %{"data" => [%{"validator_index" => "42", "slot" => "3201"}]})
      end)

      assert {:ok, [%{"validator_index" => "42"}]} = Validator.get_proposer_duties(100)
    end
  end

  describe "get_sync_duties/2" do
    test "posts validator indices and returns sync duties" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/validator/duties/sync/100"
        assert conn.method == "POST"

        Req.Test.json(conn, %{
          "data" => [%{"validator_index" => "0", "validator_sync_committee_indices" => ["5"]}]
        })
      end)

      assert {:ok, [%{"validator_index" => "0"}]} = Validator.get_sync_duties(100, ["0"])
    end
  end

  # Block production

  describe "produce_block/2" do
    test "returns an unsigned block for a slot" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v3/validator/blocks/12345"
        assert conn.method == "GET"
        Req.Test.json(conn, %{"data" => %{"message" => %{"slot" => "12345"}}})
      end)

      assert {:ok, %{"message" => %{"slot" => "12345"}}} = Validator.produce_block(12345)
    end

    test "passes randao_reveal and graffiti params" do
      Req.Test.stub(Client, fn conn ->
        assert conn.query_string =~ "randao_reveal="
        Req.Test.json(conn, %{"data" => %{}})
      end)

      assert {:ok, _} = Validator.produce_block(12345, randao_reveal: "0xabc")
    end
  end

  describe "produce_blinded_block/2" do
    test "returns an unsigned blinded block" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/validator/blinded_blocks/12345"
        Req.Test.json(conn, %{"data" => %{"message" => %{"slot" => "12345"}}})
      end)

      assert {:ok, %{"message" => _}} = Validator.produce_blinded_block(12345)
    end
  end

  # Attestation

  describe "get_attestation_data/1" do
    test "returns attestation data" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/validator/attestation_data"
        assert conn.query_string =~ "slot=100"

        Req.Test.json(conn, %{
          "data" => %{
            "slot" => "100",
            "index" => "0",
            "beacon_block_root" => "0xabc"
          }
        })
      end)

      assert {:ok, %{"slot" => "100"}} = Validator.get_attestation_data(slot: 100)
    end
  end

  describe "get_aggregate_attestation/1" do
    test "returns aggregate attestation" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/validator/aggregate_attestation"

        Req.Test.json(conn, %{
          "data" => %{"aggregation_bits" => "0xff", "data" => %{"slot" => "100"}}
        })
      end)

      assert {:ok, %{"aggregation_bits" => "0xff"}} =
               Validator.get_aggregate_attestation(
                 attestation_data_root: "0xabc",
                 slot: 100
               )
    end
  end

  describe "submit_aggregate_and_proofs/1" do
    test "submits aggregate and proofs" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/validator/aggregate_and_proofs"
        assert conn.method == "POST"
        Req.Test.json(conn, %{"data" => nil})
      end)

      assert {:ok, _} = Validator.submit_aggregate_and_proofs([%{}])
    end
  end

  # Subscriptions

  describe "submit_beacon_committee_subscriptions/1" do
    test "submits beacon committee subscriptions" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/validator/beacon_committee_subscriptions"
        assert conn.method == "POST"
        Req.Test.json(conn, %{"data" => nil})
      end)

      assert {:ok, _} = Validator.submit_beacon_committee_subscriptions([%{}])
    end
  end

  describe "submit_sync_committee_subscriptions/1" do
    test "submits sync committee subscriptions" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/validator/sync_committee_subscriptions"
        assert conn.method == "POST"
        Req.Test.json(conn, %{"data" => nil})
      end)

      assert {:ok, _} = Validator.submit_sync_committee_subscriptions([%{}])
    end
  end

  # Proposer

  describe "prepare_beacon_proposer/1" do
    test "prepares beacon proposers" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/validator/prepare_beacon_proposer"
        assert conn.method == "POST"
        Req.Test.json(conn, %{"data" => nil})
      end)

      assert {:ok, _} =
               Validator.prepare_beacon_proposer([
                 %{"validator_index" => "0", "fee_recipient" => "0xdead"}
               ])
    end
  end

  describe "register_validator/1" do
    test "registers validators with the builder network" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/validator/register_validator"
        assert conn.method == "POST"
        Req.Test.json(conn, %{"data" => nil})
      end)

      assert {:ok, _} = Validator.register_validator([%{}])
    end
  end

  # Liveness

  describe "get_liveness/2" do
    test "returns liveness data for validators" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/validator/liveness/100"
        assert conn.method == "POST"

        Req.Test.json(conn, %{
          "data" => [%{"index" => "0", "is_live" => true}]
        })
      end)

      assert {:ok, [%{"index" => "0", "is_live" => true}]} =
               Validator.get_liveness(100, ["0"])
    end
  end
end
