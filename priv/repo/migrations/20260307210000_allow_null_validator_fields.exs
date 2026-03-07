defmodule Ethercoaster.Repo.Migrations.AllowNullValidatorFields do
  use Ecto.Migration

  def change do
    alter table(:validators) do
      modify :public_key, :string, null: true
      modify :index, :integer, null: true
    end
  end
end
