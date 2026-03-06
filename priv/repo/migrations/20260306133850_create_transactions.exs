defmodule Ethercoaster.Repo.Migrations.CreateTransactions do
  use Ecto.Migration

  def change do
    create table(:transactions) do
      add :amount, :decimal, null: false
      add :datetime, :utc_datetime, null: false
      add :type_id, references(:transaction_types, on_delete: :restrict), null: false
      add :validator_id, references(:validators, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:transactions, [:type_id])
    create index(:transactions, [:validator_id])
    create index(:transactions, [:datetime])
  end
end
