defmodule Ethercoaster.Repo.Migrations.CreatePrices do
  use Ecto.Migration

  def change do
    create table(:prices) do
      add :date, :date, null: false
      add :value, :decimal, null: false
      add :token_id, references(:tokens, on_delete: :delete_all), null: false
      add :currency_id, references(:currencies, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:prices, [:date])
    create unique_index(:prices, [:date, :token_id, :currency_id])
  end
end
