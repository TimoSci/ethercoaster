defmodule Ethercoaster.ExecutionChain.ClientTest do
  use ExUnit.Case, async: true

  alias Ethercoaster.ExecutionChain.{Client, Error}

  describe "call/2" do
    test "sends a JSON-RPC request and returns the result" do
      Req.Test.stub(Client, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        assert decoded["jsonrpc"] == "2.0"
        assert decoded["method"] == "eth_blockNumber"
        assert decoded["params"] == []

        Req.Test.json(conn, %{"jsonrpc" => "2.0", "id" => decoded["id"], "result" => "0x1234"})
      end)

      assert {:ok, "0x1234"} = Client.call("eth_blockNumber")
    end

    test "passes params correctly" do
      Req.Test.stub(Client, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        assert decoded["method"] == "eth_getBalance"
        assert decoded["params"] == ["0xabc", "latest"]

        Req.Test.json(conn, %{"jsonrpc" => "2.0", "id" => decoded["id"], "result" => "0xde0b6b3a7640000"})
      end)

      assert {:ok, "0xde0b6b3a7640000"} = Client.call("eth_getBalance", ["0xabc", "latest"])
    end

    test "returns error on JSON-RPC error response" do
      Req.Test.stub(Client, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        Req.Test.json(conn, %{
          "jsonrpc" => "2.0",
          "id" => decoded["id"],
          "error" => %{"code" => -32601, "message" => "Method not found"}
        })
      end)

      assert {:error, %Error{code: -32601, message: "Method not found"}} =
               Client.call("eth_nonexistent")
    end

    test "returns error on HTTP failure" do
      Req.Test.stub(Client, fn conn ->
        Plug.Conn.send_resp(conn, 500, "Internal Server Error")
      end)

      assert {:error, %Error{message: "HTTP 500"}} = Client.call("eth_blockNumber")
    end
  end

  describe "batch/1" do
    test "sends batched JSON-RPC requests" do
      Req.Test.stub(Client, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        assert is_list(decoded)
        assert length(decoded) == 2

        results =
          Enum.map(decoded, fn req ->
            case req["method"] do
              "eth_blockNumber" ->
                %{"jsonrpc" => "2.0", "id" => req["id"], "result" => "0x100"}

              "eth_chainId" ->
                %{"jsonrpc" => "2.0", "id" => req["id"], "result" => "0x1"}
            end
          end)

        Req.Test.json(conn, results)
      end)

      results = Client.batch([{"eth_blockNumber", []}, {"eth_chainId", []}])

      assert [{:ok, "0x100"}, {:ok, "0x1"}] = results
    end

    test "handles mixed success and error in batch" do
      Req.Test.stub(Client, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        results =
          Enum.map(decoded, fn req ->
            case req["method"] do
              "eth_blockNumber" ->
                %{"jsonrpc" => "2.0", "id" => req["id"], "result" => "0x100"}

              "eth_nonexistent" ->
                %{"jsonrpc" => "2.0", "id" => req["id"], "error" => %{"code" => -32601, "message" => "Method not found"}}
            end
          end)

        Req.Test.json(conn, results)
      end)

      results = Client.batch([{"eth_blockNumber", []}, {"eth_nonexistent", []}])

      assert [{:ok, "0x100"}, {:error, %Error{code: -32601}}] = results
    end
  end
end
