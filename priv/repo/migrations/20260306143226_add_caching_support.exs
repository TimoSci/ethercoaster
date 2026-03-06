defmodule Ethercoaster.Repo.Migrations.AddCachingSupport do
  use Ecto.Migration

  def change do
    alter table(:transactions) do
      add :epoch, :integer
      add :slot, :integer
    end

    create index(:transactions, [:validator_id, :epoch])
    create unique_index(:transactions, [:validator_id, :epoch, :type_id])

    create table(:cached_epochs) do
      add :epoch, :integer, null: false
      add :category, :string, null: false
      add :validator_id, references(:validators, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:cached_epochs, [:validator_id, :epoch, :category])
  end
end
