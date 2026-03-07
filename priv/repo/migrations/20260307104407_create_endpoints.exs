defmodule Ethercoaster.Repo.Migrations.CreateEndpoints do
  use Ecto.Migration

  def change do
    create table(:endpoints) do
      add :address, :string, null: false
      add :port, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:endpoints, [:address, :port])
  end
end
