defmodule EthercoasterWeb.ValidatorHTML do
  use EthercoasterWeb, :html

  embed_templates "validator_html/*"

  @doc "Formats a Gwei integer with sign and comma delimiters, or — for nil."
  def format_gwei(val) when is_integer(val) do
    sign = if val < 0, do: "-", else: "+"
    abs_str = val |> abs() |> Integer.to_string() |> add_commas()
    "#{sign}#{abs_str}"
  end

  def format_gwei(nil), do: "—"

  @doc "Computes epoch total from an EpochRow."
  def epoch_total(row) do
    (row.att_head || 0) + (row.att_target || 0) +
      (row.att_source || 0) + (row.att_inactivity || 0) +
      (row.sync_reward || 0) + (row.proposal_total || 0)
  end

  defp add_commas(str) do
    str
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end
end
