defmodule Ethercoaster.BeaconChain.NodeTest do
  use ExUnit.Case, async: true

  alias Ethercoaster.BeaconChain.{Client, Error, Node}

  describe "get_identity/0" do
    test "returns the node identity" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/node/identity"
        assert conn.method == "GET"

        Req.Test.json(conn, %{
          "data" => %{
            "peer_id" => "QmTest123",
            "enr" => "enr:-test",
            "p2p_addresses" => ["/ip4/127.0.0.1/tcp/9000"],
            "discovery_addresses" => ["/ip4/127.0.0.1/udp/9000"],
            "metadata" => %{"seq_number" => "1"}
          }
        })
      end)

      assert {:ok, %{"peer_id" => "QmTest123"}} = Node.get_identity()
    end
  end

  describe "get_peers/1" do
    test "returns peers without filters" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/node/peers"
        Req.Test.json(conn, %{"data" => [%{"peer_id" => "Qm1"}, %{"peer_id" => "Qm2"}]})
      end)

      assert {:ok, peers} = Node.get_peers()
      assert length(peers) == 2
    end

    test "passes filter params" do
      Req.Test.stub(Client, fn conn ->
        assert conn.query_string =~ "state=connected"
        Req.Test.json(conn, %{"data" => [%{"peer_id" => "Qm1"}]})
      end)

      assert {:ok, [_peer]} = Node.get_peers(state: "connected")
    end
  end

  describe "get_peer/1" do
    test "returns a specific peer" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/node/peers/QmTest123"
        Req.Test.json(conn, %{"data" => %{"peer_id" => "QmTest123", "state" => "connected"}})
      end)

      assert {:ok, %{"peer_id" => "QmTest123"}} = Node.get_peer("QmTest123")
    end
  end

  describe "get_peer_count/0" do
    test "returns peer count summary" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/node/peer_count"

        Req.Test.json(conn, %{
          "data" => %{
            "connected" => "25",
            "connecting" => "1",
            "disconnected" => "5",
            "disconnecting" => "0"
          }
        })
      end)

      assert {:ok, %{"connected" => "25"}} = Node.get_peer_count()
    end
  end

  describe "get_version/0" do
    test "returns the node version" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/node/version"
        Req.Test.json(conn, %{"data" => %{"version" => "Lighthouse/v5.0.0-abc123"}})
      end)

      assert {:ok, %{"version" => "Lighthouse/v5.0.0-abc123"}} = Node.get_version()
    end
  end

  describe "get_syncing/0" do
    test "returns sync status" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/node/syncing"

        Req.Test.json(conn, %{
          "data" => %{
            "head_slot" => "12345",
            "sync_distance" => "0",
            "is_syncing" => false,
            "is_optimistic" => false
          }
        })
      end)

      assert {:ok, %{"is_syncing" => false}} = Node.get_syncing()
    end
  end

  describe "get_health/0" do
    test "returns {:ok, 200} when node is ready" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/node/health"
        Plug.Conn.send_resp(conn, 200, "")
      end)

      assert {:ok, 200} = Node.get_health()
    end

    test "returns {:ok, 206} when node is syncing" do
      Req.Test.stub(Client, fn conn ->
        Plug.Conn.send_resp(conn, 206, "")
      end)

      assert {:ok, 206} = Node.get_health()
    end

    test "returns error for non-healthy status" do
      Req.Test.stub(Client, fn conn ->
        conn
        |> Plug.Conn.put_status(503)
        |> Req.Test.json(%{"code" => 503, "message" => "Beacon node is not initialized"})
      end)

      assert {:error, %Error{status: 503}} = Node.get_health()
    end
  end
end
