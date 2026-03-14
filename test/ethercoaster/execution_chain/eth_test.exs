defmodule Ethercoaster.ExecutionChain.EthTest do
  use ExUnit.Case, async: true

  alias Ethercoaster.ExecutionChain.{Client, Eth}

  defp stub_rpc(method, result) do
    Req.Test.stub(Client, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert decoded["method"] == method
      Req.Test.json(conn, %{"jsonrpc" => "2.0", "id" => decoded["id"], "result" => result})
    end)
  end

  describe "block_number/0" do
    test "returns current block number" do
      stub_rpc("eth_blockNumber", "0x1234")
      assert {:ok, "0x1234"} = Eth.block_number()
    end
  end

  describe "chain_id/0" do
    test "returns chain ID" do
      stub_rpc("eth_chainId", "0x1")
      assert {:ok, "0x1"} = Eth.chain_id()
    end
  end

  describe "get_block_by_number/2" do
    test "returns block without full transactions" do
      block = %{
        "number" => "0x100",
        "hash" => "0xabc",
        "miner" => "0xfee",
        "transactions" => ["0xtx1", "0xtx2"]
      }

      Req.Test.stub(Client, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["method"] == "eth_getBlockByNumber"
        assert decoded["params"] == ["0x100", false]
        Req.Test.json(conn, %{"jsonrpc" => "2.0", "id" => decoded["id"], "result" => block})
      end)

      assert {:ok, %{"number" => "0x100", "miner" => "0xfee"}} = Eth.get_block_by_number("0x100")
    end

    test "returns block with full transactions" do
      block = %{
        "number" => "0x100",
        "miner" => "0xfee",
        "transactions" => [%{"hash" => "0xtx1", "value" => "0x0"}]
      }

      Req.Test.stub(Client, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["params"] == ["0x100", true]
        Req.Test.json(conn, %{"jsonrpc" => "2.0", "id" => decoded["id"], "result" => block})
      end)

      assert {:ok, %{"transactions" => [%{"hash" => "0xtx1"}]}} =
               Eth.get_block_by_number("0x100", true)
    end
  end

  describe "get_block_by_hash/2" do
    test "returns block by hash" do
      block = %{"number" => "0x100", "hash" => "0xabc"}

      Req.Test.stub(Client, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["method"] == "eth_getBlockByHash"
        assert decoded["params"] == ["0xabc", false]
        Req.Test.json(conn, %{"jsonrpc" => "2.0", "id" => decoded["id"], "result" => block})
      end)

      assert {:ok, %{"hash" => "0xabc"}} = Eth.get_block_by_hash("0xabc")
    end
  end

  describe "get_block_receipts/1" do
    test "returns receipts for a block" do
      receipts = [
        %{"transactionHash" => "0xtx1", "gasUsed" => "0x5208", "status" => "0x1"}
      ]

      stub_rpc("eth_getBlockReceipts", receipts)
      assert {:ok, [%{"transactionHash" => "0xtx1"}]} = Eth.get_block_receipts("0x100")
    end
  end

  describe "get_transaction_receipt/1" do
    test "returns a single transaction receipt" do
      receipt = %{"transactionHash" => "0xtx1", "gasUsed" => "0x5208"}
      stub_rpc("eth_getTransactionReceipt", receipt)
      assert {:ok, %{"transactionHash" => "0xtx1"}} = Eth.get_transaction_receipt("0xtx1")
    end
  end

  describe "get_balance/2" do
    test "returns balance of an address" do
      Req.Test.stub(Client, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["method"] == "eth_getBalance"
        assert decoded["params"] == ["0xaddr", "latest"]
        Req.Test.json(conn, %{"jsonrpc" => "2.0", "id" => decoded["id"], "result" => "0xde0b6b3a7640000"})
      end)

      assert {:ok, "0xde0b6b3a7640000"} = Eth.get_balance("0xaddr")
    end
  end
end
