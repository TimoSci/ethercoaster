defmodule Ethercoaster.TransactionCategory do
  use Ecto.Schema
  import Ecto.Changeset

  schema "transaction_categories" do
    field :name, :string

    has_many :transaction_types, Ethercoaster.TransactionType, foreign_key: :category_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
