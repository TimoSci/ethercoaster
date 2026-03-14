defmodule Ethercoaster.Repo.Migrations.AddChaintypeToEndpoints do
  use Ecto.Migration

  def change do
    alter table(:endpoints) do
      add :chaintype, :string, null: false, default: "consensus"
    end
  end
end
