# Consensus Rewards Expansion Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Expand the `/validator/query` page to show sync committee rewards and block proposal rewards alongside existing attestation rewards, with per-category query buttons.

**Architecture:** Three independent query modules (attestation, sync committee, block proposal) feed into a unified `EpochRow` struct for display. The controller dispatches to the requested category based on a `category` form param. Sync committee queries are optimized by checking duties first (skipping slot-level queries when the validator isn't on a committee).

**Tech Stack:** Elixir/Phoenix, Beacon Chain REST API, Req HTTP client, HEEx templates, daisyUI/Tailwind CSS

---

### Task 1: Add `get_block_rewards/1` to Beacon module

**Files:**
- Modify: `lib/ethercoaster/beacon_chain/beacon.ex:110-119`
- Test: `test/ethercoaster/beacon_chain/beacon_test.exs`

**Step 1: Add the function**

Add to the `# Rewards` section in `lib/ethercoaster/beacon_chain/beacon.ex`, before the attestation rewards function:

```elixir
@doc "Returns block rewards for the given `block_id`."
def get_block_rewards(block_id),
  do: Client.get("/eth/v1/beacon/rewards/blocks/#{block_id}")
```

**Step 2: Verify it compiles**

Run: `mix compile --warnings-as-errors`
Expected: compilation succeeds

**Step 3: Commit**

```bash
git add lib/ethercoaster/beacon_chain/beacon.ex
git commit -m "Add get_block_rewards/1 to Beacon module"
```

---

### Task 2: Create SyncReward struct

**Files:**
- Create: `lib/ethercoaster/validators/sync_reward.ex`

**Step 1: Create the struct**

```elixir
defmodule Ethercoaster.Validators.SyncReward do
  @moduledoc """
  Aggregated sync committee reward for one epoch (sum of per-slot rewards).

  All reward fields are integers in Gwei.
  """

  defstruct [:epoch, :validator_index, :reward]

  @type t :: %__MODULE__{
          epoch: non_neg_integer(),
          validator_index: non_neg_integer(),
          reward: integer()
        }
end
```

**Step 2: Verify it compiles**

Run: `mix compile --warnings-as-errors`

**Step 3: Commit**

```bash
git add lib/ethercoaster/validators/sync_reward.ex
git commit -m "Add SyncReward struct"
```

---

### Task 3: Create ProposalReward struct

**Files:**
- Create: `lib/ethercoaster/validators/proposal_reward.ex`

**Step 1: Create the struct**

```elixir
defmodule Ethercoaster.Validators.ProposalReward do
  @moduledoc """
  Block proposal reward for one slot.

  All reward fields are integers in Gwei.
  """

  defstruct [:epoch, :slot, :validator_index, :total]

  @type t :: %__MODULE__{
          epoch: non_neg_integer(),
          slot: non_neg_integer(),
          validator_index: non_neg_integer(),
          total: integer()
        }
end
```

**Step 2: Verify it compiles**

Run: `mix compile --warnings-as-errors`

**Step 3: Commit**

```bash
git add lib/ethercoaster/validators/proposal_reward.ex
git commit -m "Add ProposalReward struct"
```

---

### Task 4: Create EpochRow struct

**Files:**
- Create: `lib/ethercoaster/validators/epoch_row.ex`

**Step 1: Create the struct**

```elixir
defmodule Ethercoaster.Validators.EpochRow do
  @moduledoc """
  Unified row for one epoch combining all reward categories.

  Fields for unqueried categories are nil.
  """

  defstruct [
    :epoch,
    # Attestation (nil if not queried)
    :att_head,
    :att_target,
    :att_source,
    :att_inactivity,
    # Sync committee (nil if not queried)
    :sync_reward,
    # Block proposal (nil if not queried)
    :proposal_total,
    :proposal_slot
  ]

  @type t :: %__MODULE__{
          epoch: non_neg_integer(),
          att_head: integer() | nil,
          att_target: integer() | nil,
          att_source: integer() | nil,
          att_inactivity: integer() | nil,
          sync_reward: integer() | nil,
          proposal_total: integer() | nil,
          proposal_slot: non_neg_integer() | nil
        }
end
```

**Step 2: Verify it compiles**

Run: `mix compile --warnings-as-errors`

**Step 3: Commit**

```bash
git add lib/ethercoaster/validators/epoch_row.ex
git commit -m "Add EpochRow struct"
```

---

### Task 5: Expand QueryResult struct

**Files:**
- Modify: `lib/ethercoaster/validators/query_result.ex`

**Step 1: Replace the struct with expanded version**

```elixir
defmodule Ethercoaster.Validators.QueryResult do
  @moduledoc """
  Wraps the full result of a validator rewards query.
  """

  alias Ethercoaster.Validators.EpochRow

  defstruct [
    :pubkey,
    :validator_index,
    :from_epoch,
    :to_epoch,
    :epoch_count,
    :total_reward,
    :queried_categories,
    epoch_rows: []
  ]

  @type t :: %__MODULE__{
          pubkey: String.t(),
          validator_index: non_neg_integer(),
          epoch_rows: [EpochRow.t()],
          from_epoch: non_neg_integer(),
          to_epoch: non_neg_integer(),
          total_reward: integer(),
          epoch_count: non_neg_integer(),
          queried_categories: [atom()]
        }
end
```

**Step 2: Verify it compiles**

Run: `mix compile --warnings-as-errors`
Expected: Compile warnings about removed `epoch_rewards` field in `validators.ex` — that's expected, we'll fix in next task.

**Step 3: Commit**

```bash
git add lib/ethercoaster/validators/query_result.ex
git commit -m "Expand QueryResult with epoch_rows and queried_categories"
```

---

### Task 6: Refactor Validators context — extract shared helpers & add category queries

This is the largest task. We refactor `lib/ethercoaster/validators.ex` to support three category queries plus a combined query.

**Files:**
- Modify: `lib/ethercoaster/validators.ex`
- Test: `test/ethercoaster/validators_test.exs`

**Step 1: Write the tests**

Add to `test/ethercoaster/validators_test.exs`. Replace the entire file:

```elixir
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
            do: [%{"validator_index" => validator_index, "validator_sync_committee_indices" => ["0"]}],
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
        duties = Enum.map(slots, fn slot ->
          %{"slot" => to_string(slot), "validator_index" => validator_index, "pubkey" => @pubkey}
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

      assert {:ok, result} = Validators.query(@pubkey, 3200, [:attestation, :sync_committee, :block_proposal])
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
```

**Step 2: Run tests to verify they fail**

Run: `mix test test/ethercoaster/validators_test.exs`
Expected: failures because `Validators.query/3` doesn't exist yet

**Step 3: Rewrite `lib/ethercoaster/validators.ex`**

```elixir
defmodule Ethercoaster.Validators do
  @moduledoc """
  Context for querying validator consensus-layer rewards from the Beacon Chain API.

  Supports three reward categories:
  - `:attestation` — head/target/source/inactivity per epoch
  - `:sync_committee` — sync committee rewards per epoch
  - `:block_proposal` — block proposal rewards per epoch
  """

  alias Ethercoaster.BeaconChain.{Beacon, Node, Validator}
  alias Ethercoaster.Validators.{EpochRow, ProposalReward, QueryResult, SyncReward}

  @max_epochs 100
  @slots_per_epoch 32

  @type category :: :attestation | :sync_committee | :block_proposal

  @doc """
  Queries rewards for a validator over the last `last_n_slots` slots.

  `categories` is a list of reward types to fetch.
  Returns `{:ok, QueryResult.t()}` or `{:error, String.t()}`.
  """
  @spec query(String.t(), pos_integer(), [category()]) ::
          {:ok, QueryResult.t()} | {:error, String.t()}
  def query(pubkey, last_n_slots, categories) do
    with {:ok, validator_index} <- resolve_validator_index(pubkey),
         {:ok, head_slot} <- get_head_slot(),
         {:ok, {from_epoch, to_epoch}} <- compute_epoch_range(head_slot, last_n_slots) do
      index_str = Integer.to_string(validator_index)

      results =
        categories
        |> Enum.map(fn cat ->
          Task.async(fn -> {cat, fetch_category(cat, from_epoch, to_epoch, index_str)} end)
        end)
        |> Task.await_many(120_000)
        |> Map.new()

      epoch_rows = merge_epoch_rows(from_epoch, to_epoch, results, categories)

      total_reward =
        Enum.reduce(epoch_rows, 0, fn row, acc ->
          acc +
            (row.att_head || 0) + (row.att_target || 0) +
            (row.att_source || 0) + (row.att_inactivity || 0) +
            (row.sync_reward || 0) + (row.proposal_total || 0)
        end)

      {:ok,
       %QueryResult{
         pubkey: pubkey,
         validator_index: validator_index,
         epoch_rows: epoch_rows,
         from_epoch: from_epoch,
         to_epoch: to_epoch,
         total_reward: total_reward,
         epoch_count: length(epoch_rows),
         queried_categories: categories
       }}
    end
  end

  # --- Shared helpers ---

  defp resolve_validator_index(pubkey) do
    case Beacon.get_validator("head", pubkey) do
      {:ok, %{"index" => index}} -> {:ok, parse_int(index)}
      {:error, %{message: message}} -> {:error, "Validator not found: #{message}"}
      {:error, _} -> {:error, "Validator not found"}
    end
  end

  defp get_head_slot do
    case Node.get_syncing() do
      {:ok, %{"head_slot" => head_slot}} -> {:ok, parse_int(head_slot)}
      {:error, %{message: message}} -> {:error, "Could not reach beacon node: #{message}"}
      {:error, _} -> {:error, "Could not reach beacon node"}
    end
  end

  defp compute_epoch_range(head_slot, last_n_slots) do
    to_epoch = div(head_slot, @slots_per_epoch) - 1
    from_epoch = max(div(head_slot - last_n_slots, @slots_per_epoch), 0)
    from_epoch = max(from_epoch, to_epoch - @max_epochs + 1)

    if to_epoch < 0 do
      {:error, "No completed epochs yet"}
    else
      {:ok, {max(from_epoch, 0), to_epoch}}
    end
  end

  # --- Category dispatchers ---

  defp fetch_category(:attestation, from_epoch, to_epoch, index_str),
    do: fetch_attestation_rewards(from_epoch, to_epoch, index_str)

  defp fetch_category(:sync_committee, from_epoch, to_epoch, index_str),
    do: fetch_sync_rewards(from_epoch, to_epoch, index_str)

  defp fetch_category(:block_proposal, from_epoch, to_epoch, index_str),
    do: fetch_proposal_rewards(from_epoch, to_epoch, index_str)

  # --- Attestation rewards ---

  defp fetch_attestation_rewards(from_epoch, to_epoch, index_str) do
    from_epoch..to_epoch
    |> Task.async_stream(
      fn epoch ->
        case Beacon.get_attestation_rewards(Integer.to_string(epoch), [index_str]) do
          {:ok, %{"total_rewards" => [reward | _]}} ->
            {:ok,
             %{
               epoch: epoch,
               head: parse_int(reward["head"]),
               target: parse_int(reward["target"]),
               source: parse_int(reward["source"]),
               inactivity: parse_int(reward["inactivity"])
             }}

          {:error, _} ->
            :error
        end
      end,
      max_concurrency: 4,
      timeout: 30_000
    )
    |> Enum.flat_map(fn
      {:ok, {:ok, data}} -> [data]
      _ -> []
    end)
  end

  # --- Sync committee rewards ---

  defp fetch_sync_rewards(from_epoch, to_epoch, index_str) do
    # Sync committees rotate every 256 epochs.
    # Check duties once per period; only query slots if on committee.
    periods = sync_periods(from_epoch, to_epoch)

    on_committee_periods =
      periods
      |> Task.async_stream(
        fn {period_start, _period_end} ->
          epoch_str = Integer.to_string(period_start)

          case Validator.get_sync_duties(epoch_str, [index_str]) do
            {:ok, validators} when is_list(validators) and validators != [] ->
              {:on, period_start}

            _ ->
              :off
          end
        end,
        max_concurrency: 2,
        timeout: 30_000
      )
      |> Enum.flat_map(fn
        {:ok, {:on, _}} -> [:on]
        _ -> [:off]
      end)

    on_committee? = Enum.any?(on_committee_periods, &(&1 == :on))

    if on_committee? do
      # Query each slot in the epoch range
      from_epoch..to_epoch
      |> Enum.flat_map(fn epoch ->
        first_slot = epoch * @slots_per_epoch
        last_slot = first_slot + @slots_per_epoch - 1

        slot_rewards =
          first_slot..last_slot
          |> Task.async_stream(
            fn slot ->
              case Beacon.get_sync_committee_rewards(Integer.to_string(slot), [index_str]) do
                {:ok, [%{"reward" => reward} | _]} -> {:ok, parse_int(reward)}
                _ -> {:ok, 0}
              end
            end,
            max_concurrency: 8,
            timeout: 30_000
          )
          |> Enum.map(fn
            {:ok, {:ok, val}} -> val
            _ -> 0
          end)

        [%SyncReward{epoch: epoch, validator_index: parse_int(index_str), reward: Enum.sum(slot_rewards)}]
      end)
    else
      # Not on any sync committee — return zero for all epochs
      Enum.map(from_epoch..to_epoch, fn epoch ->
        %SyncReward{epoch: epoch, validator_index: parse_int(index_str), reward: 0}
      end)
    end
  end

  defp sync_periods(from_epoch, to_epoch) do
    from_period = div(from_epoch, 256)
    to_period = div(to_epoch, 256)

    Enum.map(from_period..to_period, fn period ->
      period_start = max(period * 256, from_epoch)
      period_end = min((period + 1) * 256 - 1, to_epoch)
      {period_start, period_end}
    end)
  end

  # --- Block proposal rewards ---

  defp fetch_proposal_rewards(from_epoch, to_epoch, index_str) do
    from_epoch..to_epoch
    |> Task.async_stream(
      fn epoch ->
        case Validator.get_proposer_duties(Integer.to_string(epoch)) do
          {:ok, duties} when is_list(duties) ->
            my_slots =
              duties
              |> Enum.filter(&(&1["validator_index"] == index_str))
              |> Enum.map(&parse_int(&1["slot"]))

            Enum.flat_map(my_slots, fn slot ->
              case Beacon.get_block_rewards(Integer.to_string(slot)) do
                {:ok, %{"total" => total}} ->
                  [%ProposalReward{
                    epoch: epoch,
                    slot: slot,
                    validator_index: parse_int(index_str),
                    total: parse_int(total)
                  }]

                _ ->
                  []
              end
            end)

          _ ->
            []
        end
      end,
      max_concurrency: 4,
      timeout: 30_000
    )
    |> Enum.flat_map(fn
      {:ok, proposals} -> proposals
      _ -> []
    end)
  end

  # --- Merge into EpochRows ---

  defp merge_epoch_rows(from_epoch, to_epoch, results, categories) do
    att_map =
      if :attestation in categories do
        Map.get(results, :attestation, []) |> Map.new(&{&1.epoch, &1})
      else
        %{}
      end

    sync_map =
      if :sync_committee in categories do
        Map.get(results, :sync_committee, []) |> Map.new(&{&1.epoch, &1})
      else
        %{}
      end

    proposal_map =
      if :block_proposal in categories do
        Map.get(results, :block_proposal, [])
        |> Enum.group_by(& &1.epoch)
        |> Map.new(fn {epoch, proposals} ->
          best = Enum.max_by(proposals, & &1.total, fn -> nil end)
          {epoch, best}
        end)
      else
        %{}
      end

    Enum.map(from_epoch..to_epoch, fn epoch ->
      att = Map.get(att_map, epoch)
      sync = Map.get(sync_map, epoch)
      proposal = Map.get(proposal_map, epoch)

      %EpochRow{
        epoch: epoch,
        att_head: att && att.head,
        att_target: att && att.target,
        att_source: att && att.source,
        att_inactivity: att && att.inactivity,
        sync_reward: if(:sync_committee in categories, do: (sync && sync.reward) || 0, else: nil),
        proposal_total: proposal && proposal.total,
        proposal_slot: proposal && proposal.slot
      }
    end)
  end

  defp parse_int(val) when is_integer(val), do: val
  defp parse_int(val) when is_binary(val), do: String.to_integer(val)
end
```

**Step 4: Run tests**

Run: `mix test test/ethercoaster/validators_test.exs`
Expected: all tests pass

**Step 5: Commit**

```bash
git add lib/ethercoaster/validators.ex test/ethercoaster/validators_test.exs
git commit -m "Refactor Validators to support attestation, sync committee, and block proposal queries"
```

---

### Task 7: Update ValidatorController

**Files:**
- Modify: `lib/ethercoaster_web/controllers/validator_controller.ex`
- Modify: `test/ethercoaster_web/controllers/validator_controller_test.exs`

**Step 1: Update the controller**

```elixir
defmodule EthercoasterWeb.ValidatorController do
  use EthercoasterWeb, :controller

  import Phoenix.Component, only: [to_form: 2]

  alias Ethercoaster.Validators

  @valid_categories ~w(attestation sync_committee block_proposal all)

  def query(conn, %{"validator_query" => params}) do
    pubkey = String.trim(params["pubkey"] || "")
    slots_raw = params["last_n_slots"] || ""
    category = params["category"] || "attestation"

    with {:ok, pubkey} <- validate_pubkey(pubkey),
         {:ok, last_n_slots} <- validate_slots(slots_raw),
         {:ok, categories} <- parse_categories(category) do
      case Validators.query(pubkey, last_n_slots, categories) do
        {:ok, result} ->
          render(conn, :query,
            form: to_form(%{"pubkey" => pubkey, "last_n_slots" => slots_raw}, as: :validator_query),
            result: result,
            error: nil
          )

        {:error, message} ->
          render(conn, :query,
            form: to_form(%{"pubkey" => pubkey, "last_n_slots" => slots_raw}, as: :validator_query),
            result: nil,
            error: message
          )
      end
    else
      {:error, message} ->
        render(conn, :query,
          form: to_form(%{"pubkey" => pubkey, "last_n_slots" => slots_raw}, as: :validator_query),
          result: nil,
          error: message
        )
    end
  end

  def query(conn, _params) do
    render(conn, :query,
      form: to_form(%{}, as: :validator_query),
      result: nil,
      error: nil
    )
  end

  defp validate_pubkey(pubkey) do
    if String.match?(pubkey, ~r/\A0x[0-9a-fA-F]{96}\z/) do
      {:ok, pubkey}
    else
      {:error, "Invalid public key. Must be 98 characters starting with 0x."}
    end
  end

  defp validate_slots(raw) do
    case Integer.parse(raw) do
      {n, ""} when n >= 1 and n <= 100_000 -> {:ok, n}
      _ -> {:error, "Slots must be a number between 1 and 100,000."}
    end
  end

  defp parse_categories(category) when category in @valid_categories do
    cats =
      case category do
        "all" -> [:attestation, :sync_committee, :block_proposal]
        other -> [String.to_existing_atom(other)]
      end

    {:ok, cats}
  end

  defp parse_categories(_), do: {:error, "Invalid category."}
end
```

**Step 2: Update controller tests**

Replace `test/ethercoaster_web/controllers/validator_controller_test.exs`:

```elixir
defmodule EthercoasterWeb.ValidatorControllerTest do
  use EthercoasterWeb.ConnCase

  alias Ethercoaster.BeaconChain.Client

  @pubkey "0x" <> String.duplicate("ab", 48)

  defp stub_successful_query do
    Req.Test.stub(Client, fn conn ->
      cond do
        conn.request_path =~ "/validators/" ->
          Req.Test.json(conn, %{
            "data" => %{"index" => "42", "status" => "active_ongoing"}
          })

        conn.request_path == "/eth/v1/node/syncing" ->
          Req.Test.json(conn, %{
            "data" => %{"head_slot" => "3200", "sync_distance" => "0", "is_syncing" => false}
          })

        conn.request_path =~ "/rewards/attestations/" ->
          Req.Test.json(conn, %{
            "data" => %{
              "total_rewards" => [
                %{
                  "validator_index" => "42",
                  "head" => "2000",
                  "target" => "5000",
                  "source" => "3000",
                  "inactivity" => "0"
                }
              ]
            }
          })

        conn.request_path =~ "/duties/sync/" ->
          Req.Test.json(conn, %{"data" => []})

        conn.request_path =~ "/duties/proposer/" ->
          Req.Test.json(conn, %{"data" => []})

        true ->
          Req.Test.json(conn, %{"data" => %{}})
      end
    end)
  end

  describe "GET /validator/query" do
    test "renders the query form", %{conn: conn} do
      conn = get(conn, ~p"/validator/query")
      assert html_response(conn, 200) =~ "Validator Rewards Query"
    end
  end

  describe "POST /validator/query with attestation" do
    test "renders attestation results", %{conn: conn} do
      stub_successful_query()

      conn =
        post(conn, ~p"/validator/query", %{
          "validator_query" => %{"pubkey" => @pubkey, "last_n_slots" => "3200", "category" => "attestation"}
        })

      response = html_response(conn, 200)
      assert response =~ "Validator Index"
      assert response =~ "42"
      assert response =~ "Epoch"
    end
  end

  describe "POST /validator/query with all" do
    test "renders all categories", %{conn: conn} do
      stub_successful_query()

      conn =
        post(conn, ~p"/validator/query", %{
          "validator_query" => %{"pubkey" => @pubkey, "last_n_slots" => "3200", "category" => "all"}
        })

      response = html_response(conn, 200)
      assert response =~ "Validator Index"
      assert response =~ "Epoch"
    end
  end

  describe "POST /validator/query error cases" do
    test "renders error for invalid pubkey", %{conn: conn} do
      conn =
        post(conn, ~p"/validator/query", %{
          "validator_query" => %{"pubkey" => "not-a-key", "last_n_slots" => "100", "category" => "attestation"}
        })

      assert html_response(conn, 200) =~ "Invalid public key"
    end

    test "renders error for invalid slot count", %{conn: conn} do
      conn =
        post(conn, ~p"/validator/query", %{
          "validator_query" => %{"pubkey" => @pubkey, "last_n_slots" => "0", "category" => "attestation"}
        })

      assert html_response(conn, 200) =~ "Slots must be a number"
    end

    test "renders error when API fails", %{conn: conn} do
      Req.Test.stub(Client, fn conn ->
        if conn.request_path =~ "/validators/" do
          conn
          |> Plug.Conn.put_status(404)
          |> Req.Test.json(%{"code" => 404, "message" => "Validator not found"})
        else
          Req.Test.json(conn, %{"data" => %{}})
        end
      end)

      conn =
        post(conn, ~p"/validator/query", %{
          "validator_query" => %{"pubkey" => @pubkey, "last_n_slots" => "100", "category" => "attestation"}
        })

      assert html_response(conn, 200) =~ "Validator not found"
    end
  end
end
```

**Step 3: Run tests**

Run: `mix test test/ethercoaster_web/controllers/validator_controller_test.exs`
Expected: all pass

**Step 4: Commit**

```bash
git add lib/ethercoaster_web/controllers/validator_controller.ex test/ethercoaster_web/controllers/validator_controller_test.exs
git commit -m "Update controller to support category-based reward queries"
```

---

### Task 8: Update ValidatorHTML helper and template

**Files:**
- Modify: `lib/ethercoaster_web/controllers/validator_html.ex`
- Modify: `lib/ethercoaster_web/controllers/validator_html/query.html.heex`

**Step 1: Update the HTML helper**

```elixir
defmodule EthercoasterWeb.ValidatorHTML do
  use EthercoasterWeb, :html

  embed_templates "validator_html/*"

  @doc "Formats a Gwei integer with sign and comma delimiters."
  def format_gwei(val) when is_integer(val) do
    sign = if val < 0, do: "-", else: "+"
    abs_str = val |> abs() |> Integer.to_string() |> add_commas()
    "#{sign}#{abs_str}"
  end

  def format_gwei(nil), do: "—"

  @doc "Computes epoch total from an EpochRow."
  def epoch_total(row) do
    (row.att_head || 0) + (row.att_target || 0) +
      (row.att_source || 0) + (row.att_inactivity || 0) +
      (row.sync_reward || 0) + (row.proposal_total || 0)
  end

  defp add_commas(str) do
    str
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end
end
```

**Step 2: Replace the template**

Replace `lib/ethercoaster_web/controllers/validator_html/query.html.heex`:

```heex
<.header>
  Validator Rewards Query
  <:subtitle>Query consensus-layer rewards for a validator over a range of slots.</:subtitle>
</.header>

<.form for={@form} action={~p"/validator/query"} method="post" class="mt-4 space-y-4">
  <.input field={@form[:pubkey]} type="text" label="Validator Public Key" placeholder="0x..." />
  <.input field={@form[:last_n_slots]} type="number" label="Last N Slots" placeholder="3200" min="1" max="100000" />

  <div class="flex flex-wrap gap-2 mt-2">
    <.button name="validator_query[category]" value="all" class="btn btn-primary">
      Query All Consensus
    </.button>
    <.button name="validator_query[category]" value="attestation" class="btn btn-primary btn-soft">
      Query Attestation
    </.button>
    <.button name="validator_query[category]" value="sync_committee" class="btn btn-primary btn-soft">
      Query Sync Committee
    </.button>
    <.button name="validator_query[category]" value="block_proposal" class="btn btn-primary btn-soft">
      Query Block Proposals
    </.button>
  </div>
</.form>

<div :if={@error} class="alert alert-error mt-4">
  <.icon name="hero-exclamation-circle" class="size-5" />
  <span>{@error}</span>
</div>

<div :if={@result} class="mt-6">
  <.list>
    <:item title="Public Key"><code class="text-xs break-all">{@result.pubkey}</code></:item>
    <:item title="Validator Index">{@result.validator_index}</:item>
    <:item title="Epoch Range">{@result.from_epoch} – {@result.to_epoch} ({@result.epoch_count} epochs)</:item>
    <:item title="Total Net Reward">{format_gwei(@result.total_reward)} Gwei</:item>
  </.list>

  <div class="overflow-x-auto mt-4">
    <table class="table table-zebra table-sm">
      <thead>
        <tr>
          <th rowspan="2" class="align-bottom">Epoch</th>
          <th
            :if={:attestation in @result.queried_categories}
            colspan="4"
            class="text-center border-b-0 border-l border-base-300"
          >
            Attestation
          </th>
          <th
            :if={:sync_committee in @result.queried_categories}
            class="text-center border-b-0 border-l border-base-300"
            rowspan="2"
          >
            <div class="flex flex-col items-center">
              <span>Sync</span>
              <span>Committee</span>
            </div>
          </th>
          <th
            :if={:block_proposal in @result.queried_categories}
            colspan="2"
            class="text-center border-b-0 border-l border-base-300"
          >
            Block Proposal
          </th>
          <th rowspan="2" class="align-bottom border-l border-base-300">Total</th>
        </tr>
        <tr>
          <th :if={:attestation in @result.queried_categories} class="border-l border-base-300" title="Reward for correctly attesting to the head of the chain">Head</th>
          <th :if={:attestation in @result.queried_categories} title="Reward for correctly attesting to the target checkpoint">Target</th>
          <th :if={:attestation in @result.queried_categories} title="Reward for correctly attesting to the source checkpoint">Source</th>
          <th :if={:attestation in @result.queried_categories} title="Inactivity penalty">Inact.</th>
          <th :if={:block_proposal in @result.queried_categories} class="border-l border-base-300" title="Slot where block was proposed">Slot</th>
          <th :if={:block_proposal in @result.queried_categories} title="Total block proposal reward">Reward</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={row <- @result.epoch_rows}>
          <td>{row.epoch}</td>
          <td :if={:attestation in @result.queried_categories} class="border-l border-base-300">{format_gwei(row.att_head)}</td>
          <td :if={:attestation in @result.queried_categories}>{format_gwei(row.att_target)}</td>
          <td :if={:attestation in @result.queried_categories}>{format_gwei(row.att_source)}</td>
          <td :if={:attestation in @result.queried_categories}>{format_gwei(row.att_inactivity)}</td>
          <td :if={:sync_committee in @result.queried_categories} class="border-l border-base-300">{format_gwei(row.sync_reward)}</td>
          <td :if={:block_proposal in @result.queried_categories} class="border-l border-base-300">
            {if row.proposal_slot, do: row.proposal_slot, else: "—"}
          </td>
          <td :if={:block_proposal in @result.queried_categories}>{format_gwei(row.proposal_total)}</td>
          <td class="border-l border-base-300 font-semibold">{format_gwei(epoch_total(row))}</td>
        </tr>
      </tbody>
    </table>
  </div>
</div>
```

**Step 3: Widen the page container**

In `lib/ethercoaster_web/components/layouts.ex`, change `max-w-2xl` to `max-w-5xl` on line 66:

```elixir
# Change:
<div class="mx-auto max-w-2xl space-y-4">
# To:
<div class="mx-auto max-w-5xl space-y-4">
```

**Step 4: Run all tests**

Run: `mix test`
Expected: all pass

**Step 5: Verify in browser**

Run: `mix phx.server`
Visit: `http://localhost:4000/validator/query`
Verify: Form renders with 4 buttons, table columns adjust based on category.

**Step 6: Commit**

```bash
git add lib/ethercoaster_web/controllers/validator_html.ex lib/ethercoaster_web/controllers/validator_html/query.html.heex lib/ethercoaster_web/components/layouts.ex
git commit -m "Add grouped reward columns and per-category query buttons to validator page"
```
