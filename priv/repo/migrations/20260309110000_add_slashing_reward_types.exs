defmodule Ethercoaster.Repo.Migrations.AddSlashingRewardTypes do
  use Ecto.Migration
  import Ecto.Query

  def up do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Create the "Slashing reward" event
    repo().insert_all("transaction_events", [
      %{name: "Slashing reward", inserted_at: now, updated_at: now}
    ], on_conflict: :nothing, conflict_target: :name)

    slashing_reward_event = repo().one(
      from t in "transaction_events", where: t.name == "Slashing reward", select: t.id
    )
    slashing_category = repo().one(
      from t in "transaction_categories", where: t.name == "Slashing", select: t.id
    )

    if slashing_reward_event && slashing_category do
      repo().insert_all("transaction_types", [
        %{name: "Slashing proposer reward", chain: "consensus", category_id: slashing_category, event_id: slashing_reward_event, inserted_at: now, updated_at: now},
        %{name: "Slashing whistleblower reward", chain: "consensus", category_id: slashing_category, event_id: slashing_reward_event, inserted_at: now, updated_at: now}
      ], on_conflict: :nothing, conflict_target: :name)
    end
  end

  def down do
    repo().delete_all(from t in "transaction_types", where: t.name in ["Slashing proposer reward", "Slashing whistleblower reward"])
    repo().delete_all(from t in "transaction_events", where: t.name == "Slashing reward")
  end
end
