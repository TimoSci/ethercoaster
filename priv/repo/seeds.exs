# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Ethercoaster.Repo.insert!(%Ethercoaster.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

# --- Transaction categories and types ---

alias Ethercoaster.{Repo, TransactionCategory, TransactionType}

categories = %{
  "Attestation" =>
    Repo.insert!(%TransactionCategory{name: "Attestation"},
      on_conflict: :nothing,
      conflict_target: :name
    ),
  "Sync Committee" =>
    Repo.insert!(%TransactionCategory{name: "Sync Committee"},
      on_conflict: :nothing,
      conflict_target: :name
    ),
  "Block Proposal" =>
    Repo.insert!(%TransactionCategory{name: "Block Proposal"},
      on_conflict: :nothing,
      conflict_target: :name
    ),
  "Slashing" =>
    Repo.insert!(%TransactionCategory{name: "Slashing"},
      on_conflict: :nothing,
      conflict_target: :name
    ),
  "Lifecycle" =>
    Repo.insert!(%TransactionCategory{name: "Lifecycle"},
      on_conflict: :nothing,
      conflict_target: :name
    )
}

# Reload categories to get IDs (on_conflict: :nothing returns id=nil)
categories =
  Map.new(categories, fn {name, _} ->
    {name, Repo.get_by!(TransactionCategory, name: name)}
  end)

transaction_types = [
  # Attestation
  %{name: "Head reward", event: "Attestation reward", chain: :consensus, category: "Attestation"},
  %{name: "Target reward", event: "Attestation reward", chain: :consensus, category: "Attestation"},
  %{name: "Source reward", event: "Attestation reward", chain: :consensus, category: "Attestation"},
  %{name: "Inactivity penalty", event: "Inactivity leak", chain: :consensus, category: "Attestation"},
  # Sync Committee
  %{name: "Sync committee rewards", event: "Sync committee participation", chain: :consensus, category: "Sync Committee"},
  # Block Proposal
  %{name: "Consensus proposal reward", event: "Block proposal", chain: :consensus, category: "Block Proposal"},
  %{name: "Priority fees (tips)", event: "Block proposal", chain: :execution, category: "Block Proposal"},
  %{name: "MEV rewards", event: "Block proposal", chain: :execution, category: "Block Proposal"},
  # Slashing
  %{name: "Initial + correlation penalty", event: "Slashing", chain: :consensus, category: "Slashing"},
  # Lifecycle
  %{name: "Deposit", event: "Deposit", chain: :consensus, category: "Lifecycle"},
  %{name: "Voluntary exit", event: "Voluntary exit", chain: :consensus, category: "Lifecycle"},
  %{name: "Partial withdrawal (skim)", event: "Withdrawal", chain: :consensus, category: "Lifecycle"},
  %{name: "Full withdrawal", event: "Withdrawal", chain: :consensus, category: "Lifecycle"},
  %{name: "Consolidation", event: "Consolidation", chain: :consensus, category: "Lifecycle"}
]

for type <- transaction_types do
  Repo.insert!(
    %TransactionType{
      name: type.name,
      event: type.event,
      chain: type.chain,
      category_id: categories[type.category].id
    },
    on_conflict: :nothing,
    conflict_target: :name
  )
end

IO.puts("Seeded #{length(transaction_types)} transaction types in #{map_size(categories)} categories")

# Import ESTV price CSV files
Path.wildcard(Path.join(:code.priv_dir(:ethercoaster), "repo/data/*.csv"))
|> Enum.each(fn path ->
  {:ok, count} = Ethercoaster.ESTVData.import_csv(path)
  IO.puts("Imported #{count} prices from #{Path.basename(path)}")
end)
