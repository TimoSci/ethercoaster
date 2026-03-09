defmodule Ethercoaster.ValidatorRecord do
  use Ecto.Schema
  import Ecto.Changeset

  schema "validators" do
    field :public_key, :string
    field :index, :integer
    field :exists, :boolean

    belongs_to :state, Ethercoaster.ValidatorState
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
    |> cast(attrs, [:public_key, :index, :exists, :state_id])
    |> normalize_blanks()
    |> validate_at_least_one()
    |> unique_constraint(:public_key)
    |> unique_constraint(:index)
  end

  defp normalize_blanks(changeset) do
    changeset
    |> then(fn cs ->
      case get_field(cs, :public_key) do
        "" -> put_change(cs, :public_key, nil)
        _ -> cs
      end
    end)
  end

  defp validate_at_least_one(changeset) do
    public_key = get_field(changeset, :public_key)
    index = get_field(changeset, :index)

    if (is_nil(public_key) or public_key == "") and is_nil(index) do
      add_error(changeset, :public_key, "either public key or index is required")
    else
      changeset
    end
  end
end
