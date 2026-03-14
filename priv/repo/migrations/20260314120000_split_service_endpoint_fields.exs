defmodule Ethercoaster.Repo.Migrations.SplitServiceEndpointFields do
  use Ecto.Migration

  def change do
    alter table(:services) do
      add :consensus_endpoint, :string
      add :execution_endpoint, :string
    end

    execute "UPDATE services SET consensus_endpoint = endpoint", ""

    alter table(:services) do
      remove :endpoint, :string
    end
  end
end
