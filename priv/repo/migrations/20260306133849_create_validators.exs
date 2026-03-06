defmodule Ethercoaster.Repo.Migrations.CreateValidators do
  use Ecto.Migration

  def change do
    create table(:validators) do
      add :public_key, :string, null: false
      add :index, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:validators, [:public_key])
    create unique_index(:validators, [:index])
  end
end
