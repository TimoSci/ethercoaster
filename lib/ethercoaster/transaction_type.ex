defmodule Ethercoaster.TransactionType do
  use Ecto.Schema
  import Ecto.Changeset

  schema "transaction_types" do
    field :name, :string
    field :event, :string
    field :chain, Ecto.Enum, values: [:consensus, :execution]

    belongs_to :category, Ethercoaster.TransactionCategory

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(type, attrs) do
    type
    |> cast(attrs, [:name, :event, :chain, :category_id])
    |> validate_required([:name, :event, :chain, :category_id])
    |> foreign_key_constraint(:category_id)
    |> unique_constraint(:name)
  end
end
