defmodule Ethercoaster.Repo.Migrations.AddBatchSizeToServices do
  use Ecto.Migration

  def change do
    alter table(:services) do
      add :batch_size, :integer
    end
  end
end
