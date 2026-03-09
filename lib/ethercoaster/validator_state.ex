defmodule Ethercoaster.ValidatorState do
  use Ecto.Schema

  schema "validator_states" do
    field :name, :string

    timestamps(type: :utc_datetime)
  end
end
