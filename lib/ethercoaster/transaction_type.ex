defmodule Ethercoaster.TransactionType do
  use Ecto.Schema
  import Ecto.Changeset

  schema "transaction_types" do
    field :name, :string
    field :chain, Ecto.Enum, values: [:consensus, :execution]

    belongs_to :category, Ethercoaster.TransactionCategory
    belongs_to :event, Ethercoaster.TransactionEvent

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(type, attrs) do
    type
    |> cast(attrs, [:name, :chain, :category_id, :event_id])
    |> validate_required([:name, :chain, :category_id, :event_id])
    |> foreign_key_constraint(:category_id)
    |> foreign_key_constraint(:event_id)
    |> unique_constraint(:name)
  end
end
