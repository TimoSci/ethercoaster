defmodule Ethercoaster.Repo.Migrations.CreateValidatorStates do
  use Ecto.Migration

  def up do
    create table(:validator_states) do
      add :name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:validator_states, [:name])

    flush()

    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    states =
      ~w(
        pending_initialized
        pending_queued
        active_ongoing
        active_exiting
        active_slashed
        exited_unslashed
        exited_slashed
        withdrawal_possible
        withdrawal_done
      )
      |> Enum.map(fn name -> %{name: name, inserted_at: now, updated_at: now} end)

    repo().insert_all("validator_states", states)

    alter table(:validators) do
      add :state_id, references(:validator_states, on_delete: :nilify_all), null: true
      add :exists, :boolean, null: true, default: nil
    end
  end

  def down do
    alter table(:validators) do
      remove :state_id
      remove :exists
    end

    drop table(:validator_states)
  end
end
