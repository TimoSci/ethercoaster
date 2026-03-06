defmodule Ethercoaster.Service do
  use Ecto.Schema
  import Ecto.Changeset

  schema "services" do
    field :name, :string
    field :categories, {:array, :string}, default: ["attestation"]
    field :query_mode, :string
    field :last_n_epochs, :integer
    field :epoch_from, :integer
    field :epoch_to, :integer
    field :endpoint, :string
    field :status, :string, default: "stopped"

    many_to_many :validators, Ethercoaster.ValidatorRecord,
      join_through: "services_validators",
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  def changeset(service, attrs) do
    service
    |> cast(attrs, [:name, :categories, :query_mode, :last_n_epochs, :epoch_from, :epoch_to, :endpoint, :status])
    |> validate_required([:query_mode, :categories])
    |> validate_inclusion(:query_mode, ["last_n_epochs", "epoch_range"])
    |> validate_inclusion(:status, ["stopped", "completed"])
    |> validate_query_mode_fields()
  end

  defp validate_query_mode_fields(changeset) do
    case get_field(changeset, :query_mode) do
      "last_n_epochs" ->
        validate_required(changeset, [:last_n_epochs])

      "epoch_range" ->
        changeset
        |> validate_required([:epoch_from, :epoch_to])

      _ ->
        changeset
    end
  end
end
