defmodule Ethercoaster.Repo.Migrations.CreateServices do
  use Ecto.Migration

  def change do
    create table(:services) do
      add :name, :string
      add :categories, {:array, :string}, null: false, default: ["attestation"]
      add :query_mode, :string, null: false
      add :last_n_epochs, :integer
      add :epoch_from, :integer
      add :epoch_to, :integer
      add :endpoint, :string
      add :status, :string, null: false, default: "stopped"

      timestamps(type: :utc_datetime)
    end

    create table(:services_validators, primary_key: false) do
      add :service_id, references(:services, on_delete: :delete_all), null: false
      add :validator_id, references(:validators, on_delete: :delete_all), null: false
    end

    create unique_index(:services_validators, [:service_id, :validator_id])
  end
end
