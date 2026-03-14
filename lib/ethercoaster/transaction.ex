defmodule Ethercoaster.Transaction do
  use Ecto.Schema
  import Ecto.Changeset

  schema "transactions" do
    field :amount, :decimal
    field :datetime, :utc_datetime
    field :epoch, :integer
    field :slot, :integer
    field :execution_block_hash, :string

    belongs_to :type, Ethercoaster.TransactionType
    belongs_to :validator, Ethercoaster.ValidatorRecord

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(transaction, attrs) do
    transaction
    |> cast(attrs, [:amount, :datetime, :type_id, :validator_id, :epoch, :slot, :execution_block_hash])
    |> validate_required([:amount, :datetime, :type_id, :validator_id])
    |> foreign_key_constraint(:type_id)
    |> foreign_key_constraint(:validator_id)
  end
end
