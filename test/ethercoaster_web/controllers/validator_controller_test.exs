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

        true ->
          Req.Test.json(conn, %{"data" => %{}})
      end
    end)
  end

  describe "GET /validator/query" do
    test "renders the query form", %{conn: conn} do
      conn = get(conn, ~p"/validator/query")
      assert html_response(conn, 200) =~ "Validator Rewards Query"
      assert html_response(conn, 200) =~ "Query Rewards"
    end
  end

  describe "POST /validator/query" do
    test "renders results with valid params", %{conn: conn} do
      stub_successful_query()

      conn =
        post(conn, ~p"/validator/query", %{
          "validator_query" => %{"pubkey" => @pubkey, "last_n_slots" => "3200"}
        })

      response = html_response(conn, 200)
      assert response =~ "Validator Index"
      assert response =~ "42"
      assert response =~ "Epoch"
    end

    test "renders error for invalid pubkey", %{conn: conn} do
      conn =
        post(conn, ~p"/validator/query", %{
          "validator_query" => %{"pubkey" => "not-a-key", "last_n_slots" => "100"}
        })

      response = html_response(conn, 200)
      assert response =~ "Invalid public key"
    end

    test "renders error for invalid slot count", %{conn: conn} do
      conn =
        post(conn, ~p"/validator/query", %{
          "validator_query" => %{"pubkey" => @pubkey, "last_n_slots" => "0"}
        })

      response = html_response(conn, 200)
      assert response =~ "Slots must be a number"
    end

    test "renders error for too many slots", %{conn: conn} do
      conn =
        post(conn, ~p"/validator/query", %{
          "validator_query" => %{"pubkey" => @pubkey, "last_n_slots" => "200000"}
        })

      response = html_response(conn, 200)
      assert response =~ "Slots must be a number"
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
          "validator_query" => %{"pubkey" => @pubkey, "last_n_slots" => "100"}
        })

      response = html_response(conn, 200)
      assert response =~ "Validator not found"
    end
  end
end
