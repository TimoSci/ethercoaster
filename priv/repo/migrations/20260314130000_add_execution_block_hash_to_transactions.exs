defmodule Ethercoaster.Repo.Migrations.AddExecutionBlockHashToTransactions do
  use Ecto.Migration

  def change do
    alter table(:transactions) do
      add :execution_block_hash, :string
    end
  end
end
