defmodule Ethercoaster.BeaconChain.Events.ListenerTest do
  # Not async — uses shared Req.Test mode for GenServer process access
  use ExUnit.Case

  alias Ethercoaster.BeaconChain.{Client, Events, Events.Listener}

  @moduletag :capture_log

  setup do
    # Shared mode lets the GenServer (separate process) access stubs
    Req.Test.set_req_test_to_shared()
    on_exit(fn -> Req.Test.set_req_test_to_private() end)
    :ok
  end

  describe "start_link/1" do
    test "starts the GenServer" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/events"
        Plug.Conn.send_resp(conn, 200, "")
      end)

      pid = start_supervised!({Listener, topics: ["head"]})
      assert Process.alive?(pid)
    end
  end

  describe "SSE event broadcasting" do
    test "verifies listener connects to SSE endpoint" do
      Req.Test.stub(Client, fn conn ->
        assert conn.request_path == "/eth/v1/events"
        assert conn.query_string =~ "topics=head"

        body = "event: head\ndata: {\"slot\":\"12345\",\"block\":\"0xabc\"}\n\n"

        conn
        |> Plug.Conn.put_resp_content_type("text/event-stream")
        |> Plug.Conn.send_resp(200, body)
      end)

      Events.subscribe("head")
      pid = start_supervised!({Listener, topics: ["head"]})
      assert Process.alive?(pid)
    end
  end

  describe "reconnection" do
    test "retries connection on failure" do
      call_count = :counters.new(1, [:atomics])

      Req.Test.stub(Client, fn conn ->
        :counters.add(call_count, 1, 1)

        conn
        |> Plug.Conn.put_status(503)
        |> Plug.Conn.send_resp(503, "Service Unavailable")
      end)

      pid = start_supervised!({Listener, topics: ["head"]})
      assert Process.alive?(pid)

      # Wait for initial + at least one reconnect (1s backoff)
      Process.sleep(1_500)

      assert :counters.get(call_count, 1) >= 2
    end
  end

  describe "configuration" do
    test "uses default topics when none provided" do
      Req.Test.stub(Client, fn conn ->
        query = URI.decode_query(conn.query_string)
        topics = String.split(query["topics"], ",")
        assert "head" in topics
        assert "block" in topics
        assert "attestation" in topics
        assert "finalized_checkpoint" in topics
        Plug.Conn.send_resp(conn, 200, "")
      end)

      pid = start_supervised!(Listener)
      assert Process.alive?(pid)
    end

    test "uses custom topics when provided" do
      Req.Test.stub(Client, fn conn ->
        query = URI.decode_query(conn.query_string)
        assert query["topics"] == "head,voluntary_exit"
        Plug.Conn.send_resp(conn, 200, "")
      end)

      pid = start_supervised!({Listener, topics: ["head", "voluntary_exit"]})
      assert Process.alive?(pid)
    end
  end
end
