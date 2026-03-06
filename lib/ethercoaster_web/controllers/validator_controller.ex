defmodule EthercoasterWeb.ValidatorController do
  use EthercoasterWeb, :controller

  import Phoenix.Component, only: [to_form: 2]

  alias Ethercoaster.Validator

  @valid_categories ~w(attestation sync_committee block_proposal all)

  def query(conn, %{"validator_query" => params}) do
    pubkey = String.trim(params["pubkey"] || "")
    slots_raw = params["last_n_slots"] || ""
    category = params["category"] || "attestation"

    with {:ok, pubkey} <- validate_pubkey(pubkey),
         {:ok, last_n_slots} <- validate_slots(slots_raw),
         {:ok, categories} <- parse_categories(category) do
      case Validator.query(pubkey, last_n_slots, categories) do
        {:ok, result} ->
          render(conn, :query,
            form: to_form(%{"pubkey" => pubkey, "last_n_slots" => slots_raw}, as: :validator_query),
            result: result,
            error: nil
          )

        {:error, message} ->
          render(conn, :query,
            form: to_form(%{"pubkey" => pubkey, "last_n_slots" => slots_raw}, as: :validator_query),
            result: nil,
            error: message
          )
      end
    else
      {:error, message} ->
        render(conn, :query,
          form: to_form(%{"pubkey" => pubkey, "last_n_slots" => slots_raw}, as: :validator_query),
          result: nil,
          error: message
        )
    end
  end

  def query(conn, _params) do
    render(conn, :query,
      form: to_form(%{}, as: :validator_query),
      result: nil,
      error: nil
    )
  end

  defp validate_pubkey(pubkey) do
    if String.match?(pubkey, ~r/\A0x[0-9a-fA-F]{96}\z/) do
      {:ok, pubkey}
    else
      {:error, "Invalid public key. Must be 98 characters starting with 0x."}
    end
  end

  defp validate_slots(raw) do
    case Integer.parse(raw) do
      {n, ""} when n >= 1 and n <= 100_000 -> {:ok, n}
      _ -> {:error, "Slots must be a number between 1 and 100,000."}
    end
  end

  defp parse_categories(category) when category in @valid_categories do
    cats =
      case category do
        "all" -> [:attestation, :sync_committee, :block_proposal]
        other -> [String.to_existing_atom(other)]
      end

    {:ok, cats}
  end

  defp parse_categories(_), do: {:error, "Invalid category."}
end
