defmodule EthercoasterWeb.ServiceLiveTest do
  use EthercoasterWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Ethercoaster.BeaconChain.Client
  alias Ethercoaster.{Repo, Services, ValidatorRecord}

  setup :set_req_test_from_context

  defp set_req_test_from_context(context) do
    Req.Test.set_req_test_from_context(context)
    :ok
  end

  describe "mount" do
    test "renders the services page", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/services")
      assert html =~ "Services"
      assert html =~ "Create Service"
    end
  end

  describe "pause_service" do
    test "pausing a running service stops it from fetching more batches", %{conn: conn} do
      # Track how many attestation reward requests are made
      test_pid = self()
      batch_count = :counters.new(1, [:atomics])

      # Create a validator record
      validator =
        Repo.insert!(%ValidatorRecord{public_key: "0x" <> String.duplicate("ab", 48), index: 42})

      # Create a service with epoch_range 0..999 (1000 epochs) and small batch size
      {:ok, service} =
        Services.create_service(
          %{
            query_mode: "epoch_range",
            epoch_from: 0,
            epoch_to: 999,
            categories: ["attestation"],
            batch_size: 10
          },
          [Integer.to_string(validator.index)]
        )

      # Stub the beacon API endpoints
      Req.Test.stub(Client, fn conn ->
        case conn.request_path do
          "/eth/v1/beacon/genesis" ->
            Req.Test.json(conn, %{
              "data" => %{
                "genesis_time" => "1606824023",
                "genesis_validators_root" => "0x0000",
                "genesis_fork_version" => "0x00000000"
              }
            })

          "/eth/v1/beacon/rewards/attestations/" <> _epoch ->
            :counters.add(batch_count, 1, 1)
            # Notify test process each batch call so we can detect when work is happening
            send(test_pid, :attestation_request)

            # Add a small delay to make batches take time
            Process.sleep(5)

            Req.Test.json(conn, %{
              "data" => %{
                "total_rewards" => [
                  %{
                    "validator_index" => "42",
                    "head" => "1000",
                    "target" => "2000",
                    "source" => "3000",
                    "inactivity" => "0"
                  }
                ]
              }
            })

          _ ->
            Req.Test.json(conn, %{"data" => %{}})
        end
      end)

      # Mount the LiveView
      {:ok, view, _html} = live(conn, "/services")

      # Start the service
      view |> element(~s|button[phx-click="play_service"][phx-value-id="#{service.id}"]|) |> render_click()

      # Wait for some batches to be processed (but not all 1000 epochs)
      wait_for_requests(5)

      # Pause the service
      view |> element(~s|button[phx-click="pause_service"][phx-value-id="#{service.id}"]|) |> render_click()

      # Record the count shortly after pausing (allow current batch to finish)
      Process.sleep(200)
      count_after_pause = :counters.get(batch_count, 1)

      # Wait a bit more and verify no new requests are being made
      Process.sleep(500)
      count_after_wait = :counters.get(batch_count, 1)

      # The worker should have stopped — no new requests after pause
      assert count_after_wait == count_after_pause,
             "Expected no new requests after pause, but got #{count_after_wait - count_after_pause} more"

      # Verify it didn't process all 1000 epochs (it was paused early)
      assert count_after_pause < 1000,
             "Expected fewer than 1000 requests, but got #{count_after_pause}"
    end
  end

  defp wait_for_requests(n) when n > 0 do
    receive do
      :attestation_request -> wait_for_requests(n - 1)
    after
      10_000 -> flunk("Timed out waiting for attestation requests")
    end
  end

  defp wait_for_requests(0), do: :ok
end
