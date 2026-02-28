defmodule Ethercoaster.BeaconChain.ClientTest do
  use ExUnit.Case, async: true

  alias Ethercoaster.BeaconChain.{Client, Error}

  describe "new/0" do
    test "builds a Req.Request struct" do
      req = Client.new()
      assert %Req.Request{} = req
    end

    test "uses base_url from config" do
      req = Client.new()
      assert req.options.base_url =~ "localhost"
    end
  end

  describe "get/2" do
    test "extracts data key from successful response" do
      Req.Test.stub(Client, fn conn ->
        Req.Test.json(conn, %{"data" => %{"version" => "Lighthouse/v5.0.0"}})
      end)

      assert {:ok, %{"version" => "Lighthouse/v5.0.0"}} = Client.get("/eth/v1/node/version")
    end

    test "returns full body when no data key present" do
      Req.Test.stub(Client, fn conn ->
        Req.Test.json(conn, %{"result" => "ok"})
      end)

      assert {:ok, %{"result" => "ok"}} = Client.get("/eth/v1/some/endpoint")
    end

    test "passes query params" do
      Req.Test.stub(Client, fn conn ->
        assert conn.query_string =~ "status=active"
        Req.Test.json(conn, %{"data" => []})
      end)

      assert {:ok, []} = Client.get("/eth/v1/beacon/states/head/validators", status: "active")
    end

    test "returns error for 4xx responses with JSON body" do
      Req.Test.stub(Client, fn conn ->
        conn
        |> Plug.Conn.put_status(404)
        |> Req.Test.json(%{"code" => 404, "message" => "State not found"})
      end)

      assert {:error, %Error{status: 404, code: 404, message: "State not found"}} =
               Client.get("/eth/v1/beacon/states/0xdead/root")
    end

    test "returns error for 5xx responses with JSON body" do
      Req.Test.stub(Client, fn conn ->
        conn
        |> Plug.Conn.put_status(500)
        |> Req.Test.json(%{"code" => 500, "message" => "Internal error"})
      end)

      assert {:error, %Error{status: 500, message: "Internal error"}} =
               Client.get("/eth/v1/node/syncing")
    end

    test "returns error for non-JSON error responses" do
      Req.Test.stub(Client, fn conn ->
        conn
        |> Plug.Conn.put_status(503)
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(503, "Service Unavailable")
      end)

      assert {:error, %Error{status: 503, message: "HTTP 503"}} =
               Client.get("/eth/v1/node/health")
    end

    test "returns error on transport failure" do
      Req.Test.stub(Client, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, %Error{message: message}} = Client.get("/eth/v1/node/version")
      assert message =~ "econnrefused"
    end
  end

  describe "post/3" do
    test "sends JSON body and extracts data from response" do
      Req.Test.stub(Client, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert is_list(decoded)
        Req.Test.json(conn, %{"data" => [%{"index" => "0", "slot" => "100"}]})
      end)

      assert {:ok, [%{"index" => "0", "slot" => "100"}]} =
               Client.post("/eth/v1/validator/duties/attester/1", ["0", "1"])
    end

    test "handles POST error responses" do
      Req.Test.stub(Client, fn conn ->
        conn
        |> Plug.Conn.put_status(400)
        |> Req.Test.json(%{"code" => 400, "message" => "Invalid request body"})
      end)

      assert {:error, %Error{status: 400, message: "Invalid request body"}} =
               Client.post("/eth/v1/beacon/pool/attestations", %{})
    end

    test "passes query params on POST requests" do
      Req.Test.stub(Client, fn conn ->
        assert conn.query_string =~ "foo=bar"
        Req.Test.json(conn, %{"data" => "ok"})
      end)

      assert {:ok, "ok"} = Client.post("/test", %{}, foo: "bar")
    end
  end
end
