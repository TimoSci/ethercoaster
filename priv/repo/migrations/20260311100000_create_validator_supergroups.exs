defmodule Ethercoaster.Repo.Migrations.CreateValidatorSupergroups do
  use Ecto.Migration

  def change do
    create table(:validator_supergroups) do
      add :name, :string, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:validator_supergroups, [:name])

    # Join table: supergroup <-> group (many-to-many)
    create table(:supergroup_groups, primary_key: false) do
      add :supergroup_id, references(:validator_supergroups, on_delete: :delete_all), null: false
      add :group_id, references(:validator_groups, on_delete: :delete_all), null: false
    end

    create unique_index(:supergroup_groups, [:supergroup_id, :group_id])
    create index(:supergroup_groups, [:group_id])

    # Self-referential join table: parent supergroup <-> child supergroup
    create table(:supergroup_children, primary_key: false) do
      add :parent_id, references(:validator_supergroups, on_delete: :delete_all), null: false
      add :child_id, references(:validator_supergroups, on_delete: :delete_all), null: false
    end

    create unique_index(:supergroup_children, [:parent_id, :child_id])
    create index(:supergroup_children, [:child_id])
  end
end
