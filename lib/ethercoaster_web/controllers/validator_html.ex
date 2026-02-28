defmodule EthercoasterWeb.ValidatorHTML do
  use EthercoasterWeb, :html

  embed_templates "validator_html/*"

  @doc "Formats a Gwei integer with sign and comma delimiters."
  def format_gwei(val) when is_integer(val) do
    sign = if val < 0, do: "-", else: "+"
    abs_str = val |> abs() |> Integer.to_string() |> add_commas()
    "#{sign}#{abs_str}"
  end

  defp add_commas(str) do
    str
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end
end
