defmodule Ethercoaster.Repo.Migrations.CreateTransactionEvents do
  use Ecto.Migration

  def change do
    create table(:transaction_events) do
      add :name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:transaction_events, [:name])

    alter table(:transaction_types) do
      add :event_id, references(:transaction_events, on_delete: :restrict)
    end

    create index(:transaction_types, [:event_id])

    # Backfill: not needed since we'll re-seed, but we need to drop the old column
    # after the data is migrated. We do this in a separate step.
  end
end
