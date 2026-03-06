defmodule EthercoasterWeb.ValidatorController do
  use EthercoasterWeb, :controller

  import Phoenix.Component, only: [to_form: 2]

  alias Ethercoaster.Validator

  @valid_categories ~w(attestation sync_committee block_proposal all)

  def query(conn, %{"validator_query" => params}) do
    pubkey = String.trim(params["pubkey"] || "")
    category = params["category"] || "attestation"
    form_data = Map.take(params, ~w(pubkey last_n_slots last_n_epochs from_epoch to_epoch))

    with {:ok, pubkey} <- validate_pubkey(pubkey),
         {:ok, categories} <- parse_categories(category),
         {:ok, result} <- dispatch_query(pubkey, params, categories) do
      render(conn, :query,
        form: to_form(form_data, as: :validator_query),
        result: result,
        error: nil
      )
    else
      {:error, message} ->
        render(conn, :query,
          form: to_form(form_data, as: :validator_query),
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

  defp dispatch_query(pubkey, params, categories) do
    from_raw = String.trim(params["from_epoch"] || "")
    to_raw = String.trim(params["to_epoch"] || "")
    epochs_raw = String.trim(params["last_n_epochs"] || "")
    slots_raw = String.trim(params["last_n_slots"] || "")

    cond do
      from_raw != "" and to_raw != "" ->
        with {:ok, from_epoch} <- parse_non_neg_int(from_raw, "From Epoch"),
             {:ok, to_epoch} <- parse_non_neg_int(to_raw, "To Epoch") do
          Validator.query_by_range(pubkey, from_epoch, to_epoch, categories)
        end

      epochs_raw != "" ->
        with {:ok, n} <- parse_pos_int(epochs_raw, "Last N Epochs", 1, 100) do
          Validator.query_by_epochs(pubkey, n, categories)
        end

      slots_raw != "" ->
        with {:ok, n} <- parse_pos_int(slots_raw, "Last N Slots", 1, 100_000) do
          Validator.query_by_slots(pubkey, n, categories)
        end

      true ->
        {:error, "Provide Last N Slots, Last N Epochs, or a From/To Epoch range."}
    end
  end

  defp validate_pubkey(pubkey) do
    if String.match?(pubkey, ~r/\A0x[0-9a-fA-F]{96}\z/) do
      {:ok, pubkey}
    else
      {:error, "Invalid public key. Must be 98 characters starting with 0x."}
    end
  end

  defp parse_pos_int(raw, label, min, max) do
    case Integer.parse(raw) do
      {n, ""} when n >= min and n <= max -> {:ok, n}
      _ -> {:error, "#{label} must be a number between #{min} and #{max}."}
    end
  end

  defp parse_non_neg_int(raw, label) do
    case Integer.parse(raw) do
      {n, ""} when n >= 0 -> {:ok, n}
      _ -> {:error, "#{label} must be a non-negative integer."}
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
