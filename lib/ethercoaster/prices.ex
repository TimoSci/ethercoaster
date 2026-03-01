defmodule Ethercoaster.Prices do
  import Ecto.Query

  alias Ethercoaster.{Repo, Price, Token, Currency}

  @doc """
  Imports prices from a CSV file produced by the estv_sniffer tool.

  Parses the CSV, finds-or-creates the token and currency records,
  and bulk inserts prices. Rows with empty values are skipped.

  Returns `{:ok, count}` with the number of rows inserted.
  """
  def import_csv(path) do
    lines =
      path
      |> File.stream!()
      |> Stream.map(&String.trim/1)
      |> Enum.to_list()

    [header | rows] = lines
    _columns = String.split(header, ",")

    token_symbol =
      rows
      |> Enum.find_value(fn row ->
        case String.split(row, ",") do
          [_date, token, _value, _denom] -> token
          _ -> nil
        end
      end)

    token = find_or_create_token(token_symbol)
    currency = find_or_create_currency("CHF", "Swiss Franc")

    now = DateTime.truncate(DateTime.utc_now(), :second)

    entries =
      rows
      |> Enum.filter(fn row ->
        case String.split(row, ",") do
          [_date, _token, value, _denom] -> value != ""
          _ -> false
        end
      end)
      |> Enum.map(fn row ->
        [date_str, _token, value_str, _denom] = String.split(row, ",")

        %{
          date: Date.from_iso8601!(date_str),
          value: Decimal.new(value_str),
          token_id: token.id,
          currency_id: currency.id,
          inserted_at: now,
          updated_at: now
        }
      end)

    {count, _} = Repo.insert_all(Price, entries, on_conflict: :nothing)
    {:ok, count}
  end

  @doc """
  Lists all prices for a given calendar year, preloading token and currency.
  """
  def list_prices_by_year(year) do
    start_date = Date.new!(year, 1, 1)
    end_date = Date.new!(year, 12, 31)

    Price
    |> where([p], p.date >= ^start_date and p.date <= ^end_date)
    |> order_by([p], asc: p.date)
    |> preload([:token, :currency])
    |> Repo.all()
  end

  defp find_or_create_token(symbol) do
    case Repo.get_by(Token, symbol: symbol) do
      nil ->
        %Token{}
        |> Token.changeset(%{symbol: symbol, name: symbol})
        |> Repo.insert!()

      token ->
        token
    end
  end

  defp find_or_create_currency(symbol, name) do
    case Repo.get_by(Currency, symbol: symbol) do
      nil ->
        %Currency{}
        |> Currency.changeset(%{symbol: symbol, name: name})
        |> Repo.insert!()

      currency ->
        currency
    end
  end
end
