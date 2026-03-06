defmodule Ethercoaster.Repo.Migrations.CreateTransactionCategories do
  use Ecto.Migration

  def change do
    create table(:transaction_categories) do
      add :name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:transaction_categories, [:name])
  end
end
