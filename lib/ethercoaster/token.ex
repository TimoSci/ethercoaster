defmodule Ethercoaster.Token do
  use Ecto.Schema
  import Ecto.Changeset

  schema "tokens" do
    field :name, :string
    field :symbol, :string

    has_many :prices, Ethercoaster.Price

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(token, attrs) do
    token
    |> cast(attrs, [:name, :symbol])
    |> validate_required([:name, :symbol])
  end
end
