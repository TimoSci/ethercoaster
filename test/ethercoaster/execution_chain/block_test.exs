defmodule Ethercoaster.ExecutionChain.BlockTest do
  use ExUnit.Case, async: true

  alias Ethercoaster.ExecutionChain.{Block, Client}

  # Simulates a realistic post-merge Ethereum block with 3 transactions.
  # Block base fee: 10 Gwei (0x2540BE400)
  # Tx1: gas price 15 Gwei, used 21000 gas → tip = 5 Gwei * 21000 = 105,000 Gwei
  # Tx2: gas price 12 Gwei, used 50000 gas → tip = 2 Gwei * 50000 = 100,000 Gwei
  # Tx3: gas price 20 Gwei, used 100000 gas → tip = 10 Gwei * 100000 = 1,000,000 Gwei
  # Total tips = 1,205,000 Gwei = 1,205,000,000,000,000 wei

  @block_number "0x12D687"
  @fee_recipient "0x388C818CA8B9251b393131C08a736A67ccB19297"
  @base_fee_wei 10_000_000_000

  @block_data %{
    "number" => @block_number,
    "hash" => "0xabc123",
    "miner" => @fee_recipient,
    "baseFeePerGas" => "0x" <> Integer.to_string(@base_fee_wei, 16),
    "gasUsed" => "0x29E58",
    "transactions" => [
      %{
        "hash" => "0xtx1",
        "gasPrice" => "0x" <> Integer.to_string(15_000_000_000, 16)
      },
      %{
        "hash" => "0xtx2",
        "gasPrice" => "0x" <> Integer.to_string(12_000_000_000, 16)
      },
      %{
        "hash" => "0xtx3",
        "gasPrice" => "0x" <> Integer.to_string(20_000_000_000, 16)
      }
    ]
  }

  @receipts [
    %{
      "transactionHash" => "0xtx1",
      "gasUsed" => "0x5208",
      "effectiveGasPrice" => "0x" <> Integer.to_string(15_000_000_000, 16)
    },
    %{
      "transactionHash" => "0xtx2",
      "gasUsed" => "0xC350",
      "effectiveGasPrice" => "0x" <> Integer.to_string(12_000_000_000, 16)
    },
    %{
      "transactionHash" => "0xtx3",
      "gasUsed" => "0x186A0",
      "effectiveGasPrice" => "0x" <> Integer.to_string(20_000_000_000, 16)
    }
  ]

  defp stub_block_and_receipts(block_data, receipts) do
    Req.Test.stub(Client, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)

      result =
        case decoded["method"] do
          "eth_getBlockByNumber" -> block_data
          "eth_getBlockReceipts" -> receipts
        end

      Req.Test.json(conn, %{"jsonrpc" => "2.0", "id" => decoded["id"], "result" => result})
    end)
  end

  describe "get_block_rewards/1" do
    test "returns block rewards, validator, and fee recipient" do
      stub_block_and_receipts(@block_data, @receipts)

      assert {:ok, result} = Block.get_block_rewards(@block_number)

      assert result.block_number == 0x12D687
      assert result.validator == @fee_recipient
      assert result.fee_recipient == @fee_recipient
      assert result.base_fee_per_gas == @base_fee_wei

      # Tx1: (15 - 10) Gwei * 21000 = 105,000 Gwei = 105,000,000,000,000 wei
      # Tx2: (12 - 10) Gwei * 50000 = 100,000 Gwei = 100,000,000,000,000 wei
      # Tx3: (20 - 10) Gwei * 100000 = 1,000,000 Gwei = 1,000,000,000,000,000 wei
      # Total: 1,205,000 Gwei = 1,205,000,000,000,000 wei
      expected_tips =
        5_000_000_000 * 21_000 +
          2_000_000_000 * 50_000 +
          10_000_000_000 * 100_000

      assert result.total_priority_fees == expected_tips
      assert result.block_reward == expected_tips
    end

    test "accepts integer block numbers" do
      stub_block_and_receipts(@block_data, @receipts)

      assert {:ok, result} = Block.get_block_rewards(1_234_567)
      assert result.block_number == 0x12D687
    end

    test "returns error for non-existent block" do
      Req.Test.stub(Client, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        Req.Test.json(conn, %{"jsonrpc" => "2.0", "id" => decoded["id"], "result" => nil})
      end)

      assert {:error, :block_not_found} = Block.get_block_rewards("0xFFFFFFFF")
    end

    test "handles block with no transactions (empty block)" do
      empty_block = %{
        "number" => "0x100",
        "hash" => "0xdef",
        "miner" => @fee_recipient,
        "baseFeePerGas" => "0x2540BE400",
        "gasUsed" => "0x0",
        "transactions" => []
      }

      stub_block_and_receipts(empty_block, [])

      assert {:ok, result} = Block.get_block_rewards("0x100")
      assert result.total_priority_fees == 0
      assert result.block_reward == 0
      assert result.validator == @fee_recipient
    end

    test "handles pre-EIP-1559 block (no baseFeePerGas)" do
      legacy_block = %{
        "number" => "0x100",
        "miner" => @fee_recipient,
        "gasUsed" => "0x5208",
        "transactions" => [
          %{"hash" => "0xtx1", "gasPrice" => "0x4A817C800"}
        ]
      }

      legacy_receipts = [
        %{
          "transactionHash" => "0xtx1",
          "gasUsed" => "0x5208",
          "effectiveGasPrice" => "0x4A817C800"
        }
      ]

      stub_block_and_receipts(legacy_block, legacy_receipts)

      assert {:ok, result} = Block.get_block_rewards("0x100")
      assert result.base_fee_per_gas == 0
      # With no base fee, the entire gas price is the "tip"
      # 20 Gwei * 21000 = 420,000 Gwei
      assert result.total_priority_fees == 20_000_000_000 * 21_000
    end
  end

  describe "get_block_rewards_batch/1" do
    test "returns rewards for multiple blocks" do
      block1 = %{
        "number" => "0x100",
        "miner" => @fee_recipient,
        "baseFeePerGas" => "0x2540BE400",
        "gasUsed" => "0x5208",
        "transactions" => [%{"hash" => "0xtx1"}]
      }

      receipts1 = [
        %{
          "transactionHash" => "0xtx1",
          "gasUsed" => "0x5208",
          "effectiveGasPrice" => "0x" <> Integer.to_string(15_000_000_000, 16)
        }
      ]

      block2 = %{
        "number" => "0x101",
        "miner" => @fee_recipient,
        "baseFeePerGas" => "0x2540BE400",
        "gasUsed" => "0x0",
        "transactions" => []
      }

      Req.Test.stub(Client, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        results =
          Enum.map(decoded, fn req ->
            result =
              case {req["method"], req["params"]} do
                {"eth_getBlockByNumber", ["0x100", true]} -> block1
                {"eth_getBlockReceipts", ["0x100"]} -> receipts1
                {"eth_getBlockByNumber", ["0x101", true]} -> block2
                {"eth_getBlockReceipts", ["0x101"]} -> []
              end

            %{"jsonrpc" => "2.0", "id" => req["id"], "result" => result}
          end)

        Req.Test.json(conn, results)
      end)

      results = Block.get_block_rewards_batch([0x100, 0x101])

      assert [{:ok, r1}, {:ok, r2}] = results
      assert r1.block_number == 0x100
      assert r1.total_priority_fees == 5_000_000_000 * 21_000
      assert r2.block_number == 0x101
      assert r2.total_priority_fees == 0
    end
  end
end
