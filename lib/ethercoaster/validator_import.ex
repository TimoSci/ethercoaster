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
end
