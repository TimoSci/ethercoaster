defmodule Ethercoaster.ValidatorRecord do
  use Ecto.Schema
  import Ecto.Changeset

  schema "validators" do
    field :public_key, :string
    field :index, :integer

    has_many :transactions, Ethercoaster.Transaction, foreign_key: :validator_id

    many_to_many :groups, Ethercoaster.ValidatorGroup,
      join_through: "validator_groups_validators",
      join_keys: [validator_id: :id, validator_group_id: :id],
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(validator, attrs) do
    validator
    |> cast(attrs, [:public_key, :index])
    |> validate_required([:public_key, :index])
    |> unique_constraint(:public_key)
    |> unique_constraint(:index)
  end
end
