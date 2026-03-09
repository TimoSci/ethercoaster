defmodule Ethercoaster.Repo.Migrations.SplitSlashingPenaltyTypes do
  use Ecto.Migration
  import Ecto.Query

  def up do
    # Get the slashing event and category IDs
    slashing_event = repo().one(
      from t in "transaction_events", where: t.name == "Slashing", select: t.id
    )
    slashing_category = repo().one(
      from t in "transaction_categories", where: t.name == "Slashing", select: t.id
    )

    if slashing_event && slashing_category do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # Insert new types
      repo().insert_all("transaction_types", [
        %{name: "Slashing initial penalty", chain: "consensus", category_id: slashing_category, event_id: slashing_event, inserted_at: now, updated_at: now},
        %{name: "Slashing correlation penalty", chain: "consensus", category_id: slashing_category, event_id: slashing_event, inserted_at: now, updated_at: now}
      ], on_conflict: :nothing, conflict_target: :name)

      # Remove old combined type if no transactions reference it
      old_type = repo().one(
        from t in "transaction_types", where: t.name == "Initial + correlation penalty", select: t.id
      )

      if old_type do
        has_txns = repo().one(
          from t in "transactions", where: t.type_id == ^old_type, select: count(t.id)
        )

        if has_txns == 0 do
          repo().delete_all(from t in "transaction_types", where: t.id == ^old_type)
        end
      end
    end
  end

  def down do
    repo().delete_all(from t in "transaction_types", where: t.name in ["Slashing initial penalty", "Slashing correlation penalty"])
  end
end
