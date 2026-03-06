defmodule Ethercoaster.TransactionEvent do
  use Ecto.Schema
  import Ecto.Changeset

  schema "transaction_events" do
    field :name, :string

    has_many :transaction_types, Ethercoaster.TransactionType, foreign_key: :event_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
