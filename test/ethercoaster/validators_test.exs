defmodule Ethercoaster.ValidatorsTest do
  use ExUnit.Case, async: true

  alias Ethercoaster.BeaconChain.Client
  alias Ethercoaster.Validators

  @pubkey "0x" <> String.duplicate("ab", 48)

  # --- Stubs ---

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

  defp stub_sync_duties(validator_index, on_committee: on_committee) do
    fn conn ->
      if conn.request_path =~ "/duties/sync/" do
        validators =
          if on_committee,
            do: [
              %{
                "validator_index" => validator_index,
                "validator_sync_committee_indices" => ["0"]
              }
            ],
            else: []

        Req.Test.json(conn, %{"data" => validators})
      else
        conn
      end
    end
  end

  defp stub_sync_committee_rewards(validator_index, reward) do
    fn conn ->
      if conn.request_path =~ "/rewards/sync_committee/" do
        Req.Test.json(conn, %{
          "data" => [%{"validator_index" => validator_index, "reward" => reward}]
        })
      else
        conn
      end
    end
  end

  defp stub_proposer_duties(validator_index, slots) do
    fn conn ->
      if conn.request_path =~ "/duties/proposer/" do
        duties =
          Enum.map(slots, fn slot ->
            %{
              "slot" => to_string(slot),
              "validator_index" => validator_index,
              "pubkey" => @pubkey
            }
          end)

        Req.Test.json(conn, %{"data" => duties})
      else
        conn
      end
    end
  end

  defp stub_block_rewards(total) do
    fn conn ->
      if conn.request_path =~ "/rewards/blocks/" do
        Req.Test.json(conn, %{
          "data" => %{
            "proposer_index" => "42",
            "total" => total,
            "attestations" => total,
            "sync_aggregate" => "0",
            "proposer_slashings" => "0",
            "attester_slashings" => "0"
          }
        })
      else
        conn
      end
    end
  end

  defp chain_stubs(stubs) do
    Req.Test.stub(Client, fn conn ->
      Enum.reduce(stubs, conn, fn stub, acc ->
        case acc do
          %Plug.Conn{state: :sent} -> acc
          _ -> stub.(acc)
        end
      end)
    end)
  end

  # --- Attestation rewards ---

  describe "query/3 attestation" do
    test "returns attestation rewards" do
      chain_stubs([
        stub_validator("42"),
        stub_syncing("3200"),
        stub_attestation_rewards("42")
      ])

      assert {:ok, result} = Validators.query(@pubkey, 3200, [:attestation])
      assert result.pubkey == @pubkey
      assert result.validator_index == 42
      assert :attestation in result.queried_categories
      assert length(result.epoch_rows) > 0

      row = hd(result.epoch_rows)
      assert row.att_head == 2000
      assert row.att_target == 5000
      assert row.att_source == 3000
      assert row.att_inactivity == 0
      assert row.sync_reward == nil
      assert row.proposal_total == nil
    end
  end

  # --- Sync committee rewards ---

  describe "query/3 sync_committee" do
    test "returns sync rewards when on committee" do
      chain_stubs([
        stub_validator("42"),
        stub_syncing("3200"),
        stub_sync_duties("42", on_committee: true),
        stub_sync_committee_rewards("42", "500")
      ])

      assert {:ok, result} = Validators.query(@pubkey, 3200, [:sync_committee])
      assert :sync_committee in result.queried_categories
      assert length(result.epoch_rows) > 0

      row = hd(result.epoch_rows)
      assert is_integer(row.sync_reward)
      assert row.att_head == nil
    end

    test "returns zero sync rewards when not on committee" do
      chain_stubs([
        stub_validator("42"),
        stub_syncing("3200"),
        stub_sync_duties("42", on_committee: false)
      ])

      assert {:ok, result} = Validators.query(@pubkey, 3200, [:sync_committee])
      assert :sync_committee in result.queried_categories
      assert length(result.epoch_rows) > 0

      row = hd(result.epoch_rows)
      assert row.sync_reward == 0
    end
  end

  # --- Block proposal rewards ---

  describe "query/3 block_proposal" do
    test "returns proposal rewards when validator proposed" do
      chain_stubs([
        stub_validator("42"),
        stub_syncing("3200"),
        stub_proposer_duties("42", [3168]),
        stub_block_rewards("50000")
      ])

      assert {:ok, result} = Validators.query(@pubkey, 3200, [:block_proposal])
      assert :block_proposal in result.queried_categories

      rows_with_proposals = Enum.filter(result.epoch_rows, & &1.proposal_total)
      assert length(rows_with_proposals) >= 1
      assert hd(rows_with_proposals).proposal_total == 50000
    end

    test "returns nil proposal when validator did not propose" do
      chain_stubs([
        stub_validator("42"),
        stub_syncing("3200"),
        stub_proposer_duties("99", [3168])
      ])

      assert {:ok, result} = Validators.query(@pubkey, 3200, [:block_proposal])
      assert Enum.all?(result.epoch_rows, &is_nil(&1.proposal_total))
    end
  end

  # --- Combined query ---

  describe "query/3 all categories" do
    test "returns all categories" do
      chain_stubs([
        stub_validator("42"),
        stub_syncing("3200"),
        stub_attestation_rewards("42"),
        stub_sync_duties("42", on_committee: false),
        stub_proposer_duties("99", [])
      ])

      assert {:ok, result} =
               Validators.query(@pubkey, 3200, [:attestation, :sync_committee, :block_proposal])

      assert :attestation in result.queried_categories
      assert :sync_committee in result.queried_categories
      assert :block_proposal in result.queried_categories
    end
  end

  # --- Error cases ---

  describe "query/3 validator not found" do
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

      assert {:error, message} = Validators.query(@pubkey, 100, [:attestation])
      assert message =~ "Validator not found"
    end
  end

  describe "query/3 node unreachable" do
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

      assert {:error, message} = Validators.query(@pubkey, 100, [:attestation])
      assert message =~ "beacon node"
    end
  end
end
