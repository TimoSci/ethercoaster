defmodule Ethercoaster.Repo.Migrations.CreateTransactionTypes do
  use Ecto.Migration

  def change do
    create table(:transaction_types) do
      add :name, :string, null: false
      add :event, :string, null: false
      add :chain, :string, null: false
      add :category_id, references(:transaction_categories, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:transaction_types, [:category_id])
    create unique_index(:transaction_types, [:name])
  end
end
