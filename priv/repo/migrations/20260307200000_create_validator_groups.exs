defmodule Ethercoaster.Repo.Migrations.CreateValidatorGroups do
  use Ecto.Migration

  def change do
    create table(:validator_groups) do
      add :name, :string, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:validator_groups, [:name])

    create table(:validator_groups_validators, primary_key: false) do
      add :validator_group_id, references(:validator_groups, on_delete: :delete_all), null: false
      add :validator_id, references(:validators, on_delete: :delete_all), null: false
    end

    create unique_index(:validator_groups_validators, [:validator_group_id, :validator_id])
    create index(:validator_groups_validators, [:validator_id])
  end
end
