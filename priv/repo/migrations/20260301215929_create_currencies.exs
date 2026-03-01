defmodule Ethercoaster.Repo.Migrations.CreateCurrencies do
  use Ecto.Migration

  def change do
    create table(:currencies) do
      add :name, :string
      add :symbol, :string

      timestamps(type: :utc_datetime)
    end
  end
end
