defmodule Ethercoaster.Repo.Migrations.DropEventStringFromTransactionTypes do
  use Ecto.Migration

  def change do
    alter table(:transaction_types) do
      remove :event, :string, null: false
    end
  end
end
