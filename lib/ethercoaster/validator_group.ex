defmodule Ethercoaster.ValidatorGroup do
  use Ecto.Schema
  import Ecto.Changeset

  schema "validator_groups" do
    field :name, :string

    many_to_many :validators, Ethercoaster.ValidatorRecord,
      join_through: "validator_groups_validators",
      join_keys: [validator_group_id: :id, validator_id: :id],
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  def changeset(group, attrs) do
    group
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
