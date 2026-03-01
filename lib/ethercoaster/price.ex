defmodule Ethercoaster.Price do
  use Ecto.Schema
  import Ecto.Changeset

  schema "prices" do
    field :date, :date
    field :value, :decimal

    belongs_to :token, Ethercoaster.Token
    belongs_to :currency, Ethercoaster.Currency

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(price, attrs) do
    price
    |> cast(attrs, [:date, :value, :token_id, :currency_id])
    |> validate_required([:date, :value, :token_id, :currency_id])
    |> foreign_key_constraint(:token_id)
    |> foreign_key_constraint(:currency_id)
    |> unique_constraint([:date, :token_id, :currency_id])
  end
end
