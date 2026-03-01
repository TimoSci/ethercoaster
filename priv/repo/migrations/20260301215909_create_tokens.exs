defmodule Ethercoaster.Repo.Migrations.CreateTokens do
  use Ecto.Migration

  def change do
    create table(:tokens) do
      add :name, :string
      add :symbol, :string

      timestamps(type: :utc_datetime)
    end
  end
end
