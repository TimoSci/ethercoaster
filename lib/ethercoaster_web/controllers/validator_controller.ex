defmodule EthercoasterWeb.ValidatorController do
  use EthercoasterWeb, :controller

  import Phoenix.Component, only: [to_form: 2]

  alias Ethercoaster.Validators

  def query(conn, %{"validator_query" => params}) do
    pubkey = String.trim(params["pubkey"] || "")
    slots_raw = params["last_n_slots"] || ""

    with {:ok, pubkey} <- validate_pubkey(pubkey),
         {:ok, last_n_slots} <- validate_slots(slots_raw) do
      case Validators.query_rewards(pubkey, last_n_slots) do
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
      {n, ""} when n >= 1 and n <= 100_000 ->
        {:ok, n}

      _ ->
        {:error, "Slots must be a number between 1 and 100,000."}
    end
  end
end
