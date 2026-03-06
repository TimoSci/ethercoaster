defmodule Ethercoaster.Repo.Migrations.AddChainCheckConstraint do
  use Ecto.Migration

  def change do
    create constraint(:transaction_types, :chain_must_be_valid,
      check: "chain IN ('consensus', 'execution')"
    )
  end
end
