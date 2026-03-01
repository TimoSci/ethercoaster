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

# Import ESTV price CSV files
Path.wildcard(Path.join(:code.priv_dir(:ethercoaster), "repo/data/*.csv"))
|> Enum.each(fn path ->
  {:ok, count} = Ethercoaster.Prices.import_csv(path)
  IO.puts("Imported #{count} prices from #{Path.basename(path)}")
end)
