defmodule Ethercoaster.ValidatorSupergroup do
  use Ecto.Schema
  import Ecto.Changeset

  schema "validator_supergroups" do
    field :name, :string

    many_to_many :groups, Ethercoaster.ValidatorGroup,
      join_through: "supergroup_groups",
      join_keys: [supergroup_id: :id, group_id: :id],
      on_replace: :delete

    many_to_many :children, Ethercoaster.ValidatorSupergroup,
      join_through: "supergroup_children",
      join_keys: [parent_id: :id, child_id: :id],
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  def changeset(supergroup, attrs) do
    supergroup
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
