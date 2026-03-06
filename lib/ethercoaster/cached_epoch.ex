defmodule Ethercoaster.CachedEpoch do
  use Ecto.Schema
  import Ecto.Changeset

  schema "cached_epochs" do
    field :epoch, :integer
    field :category, :string

    belongs_to :validator, Ethercoaster.ValidatorRecord

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(cached_epoch, attrs) do
    cached_epoch
    |> cast(attrs, [:epoch, :category, :validator_id])
    |> validate_required([:epoch, :category, :validator_id])
    |> unique_constraint([:validator_id, :epoch, :category])
  end
end
