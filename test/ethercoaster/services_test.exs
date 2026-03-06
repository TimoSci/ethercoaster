defmodule Ethercoaster.ServicesTest do
  use Ethercoaster.DataCase, async: true

  alias Ethercoaster.Services
  alias Ethercoaster.ValidatorRecord

  @pubkey "0x" <> String.duplicate("ab", 48)

  describe "create_service/2" do
    test "creates a service with validators by pubkey" do
      Repo.insert!(%ValidatorRecord{public_key: @pubkey, index: 42})

      attrs = %{
        name: "Test Service",
        query_mode: "last_n_epochs",
        last_n_epochs: 50,
        categories: ["attestation"]
      }

      assert {:ok, service} = Services.create_service(attrs, [@pubkey])
      assert service.name == "Test Service"
      assert service.query_mode == "last_n_epochs"
      assert service.last_n_epochs == 50
      assert service.status == "stopped"
      assert length(service.validators) == 1
      assert hd(service.validators).public_key == @pubkey
    end

    test "creates a service with validator by index" do
      Repo.insert!(%ValidatorRecord{public_key: "unresolved:42", index: 42})

      attrs = %{
        query_mode: "epoch_range",
        epoch_from: 0,
        epoch_to: 99,
        categories: ["attestation"]
      }

      assert {:ok, service} = Services.create_service(attrs, ["42"])
      assert length(service.validators) == 1
    end

    test "returns error for invalid query_mode" do
      Repo.insert!(%ValidatorRecord{public_key: @pubkey, index: 42})

      attrs = %{
        query_mode: "invalid",
        categories: ["attestation"]
      }

      assert {:error, _} = Services.create_service(attrs, [@pubkey])
    end
  end

  describe "list_services/0" do
    test "returns services ordered by newest first" do
      Repo.insert!(%ValidatorRecord{public_key: @pubkey, index: 42})

      {:ok, _s1} =
        Services.create_service(
          %{name: "First", query_mode: "last_n_epochs", last_n_epochs: 10, categories: ["attestation"]},
          [@pubkey]
        )

      {:ok, s2} =
        Services.create_service(
          %{name: "Second", query_mode: "last_n_epochs", last_n_epochs: 20, categories: ["attestation"]},
          [@pubkey]
        )

      services = Services.list_services()
      assert length(services) == 2
      assert hd(services).id == s2.id
    end
  end

  describe "delete_service/1" do
    test "deletes a service" do
      Repo.insert!(%ValidatorRecord{public_key: @pubkey, index: 42})

      {:ok, service} =
        Services.create_service(
          %{name: "To Delete", query_mode: "last_n_epochs", last_n_epochs: 10, categories: ["attestation"]},
          [@pubkey]
        )

      assert {:ok, _} = Services.delete_service(service.id)
      assert Services.list_services() == []
    end
  end
end
