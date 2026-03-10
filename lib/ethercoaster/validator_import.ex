defmodule Ethercoaster.ValidatorImport do
  @moduledoc """
  Shared logic for parsing validator import files (CSV and JSON).
  """

  def parse_file(content, filename) do
    cond do
      String.ends_with?(filename, ".json") ->
        case Jason.decode(content) do
          {:ok, list} when is_list(list) ->
            {:ok, Enum.map(list, &to_string/1)}

          {:ok, %{"validators" => list}} when is_list(list) ->
            {:ok, Enum.map(list, &to_string/1)}

          _ ->
            {:error, "JSON must be an array of validators or {\"validators\": [...]}"}
        end

      String.ends_with?(filename, ".csv") ->
        lines =
          content
          |> String.split(["\n", "\r\n"])
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))

        {:ok, lines}

      true ->
        {:error, "Unsupported file type"}
    end
  end

  @pubkey_regex ~r/0x[0-9a-fA-F]{96}/

  @doc """
  Fuzzy import: regex-scans content for valid validator public keys.
  Returns `{:ok, %{groups: %{path => [pubkeys]}, flat: [pubkeys]}}`.
  For JSON files, keys at the same hierarchy level are grouped together.
  For CSV/other, all keys are returned in the flat list.
  """
  def fuzzy_parse_file(content, filename) do
    if String.ends_with?(filename, ".json") do
      fuzzy_parse_json(content)
    else
      keys = Regex.scan(@pubkey_regex, content) |> List.flatten() |> Enum.uniq()
      {:ok, %{groups: %{}, flat: keys}}
    end
  end

  defp fuzzy_parse_json(content) do
    case Jason.decode(content) do
      {:ok, decoded} ->
        pairs = walk_json(decoded, [])
        {grouped, ungrouped} = Enum.split_with(pairs, fn {path, _} -> path != [] end)

        groups =
          grouped
          |> Enum.group_by(fn {path, _} -> Enum.join(path, "/") end, fn {_, key} -> key end)
          |> Enum.map(fn {name, keys} -> {name, Enum.uniq(keys)} end)
          |> Enum.into(%{})

        flat = ungrouped |> Enum.map(fn {_, key} -> key end) |> Enum.uniq()
        {:ok, %{groups: groups, flat: flat}}

      {:error, _} ->
        # JSON didn't parse — fall back to raw regex scan
        keys = Regex.scan(@pubkey_regex, content) |> List.flatten() |> Enum.uniq()
        {:ok, %{groups: %{}, flat: keys}}
    end
  end

  defp walk_json(value, path) when is_binary(value) do
    Regex.scan(@pubkey_regex, value)
    |> List.flatten()
    |> Enum.map(&{path, &1})
  end

  defp walk_json(value, _path) when is_number(value) or is_boolean(value) or is_nil(value), do: []

  defp walk_json(list, path) when is_list(list) do
    Enum.flat_map(list, &walk_json(&1, path))
  end

  defp walk_json(map, path) when is_map(map) do
    Enum.flat_map(map, fn {k, v} -> walk_json(v, path ++ [k]) end)
  end
end
