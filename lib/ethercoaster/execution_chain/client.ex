defmodule Ethercoaster.ExecutionChain.Client do
  @moduledoc """
  HTTP JSON-RPC client for the Ethereum execution layer.

  All EL nodes expose a JSON-RPC interface (typically on port 8545).
  This module sends `{"jsonrpc":"2.0", ...}` requests via `Req` and
  unwraps the `"result"` field on success.
  """

  alias Ethercoaster.ExecutionChain.Error

  @base_url_key :execution_chain_base_url

  @doc """
  Sets a per-process base URL override for execution layer calls.
  """
  def put_base_url(nil), do: :ok
  def put_base_url(url), do: Process.put(@base_url_key, url)

  @doc """
  Returns the current per-process base URL override, or nil.
  """
  def get_base_url, do: Process.get(@base_url_key)

  @doc """
  Sends a JSON-RPC call and returns `{:ok, result}` or `{:error, %Error{}}`.
  """
  @spec call(String.t(), list()) :: {:ok, term()} | {:error, Error.t()}
  def call(method, params \\ []) do
    body = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => method,
      "params" => params
    }

    new()
    |> Req.post(json: body)
    |> handle_response()
  end

  @doc """
  Sends a batch of JSON-RPC calls and returns a list of `{:ok, result} | {:error, %Error{}}`.
  """
  @spec batch([{String.t(), list()}]) :: [{:ok, term()} | {:error, Error.t()}]
  def batch(calls) do
    body =
      calls
      |> Enum.with_index(1)
      |> Enum.map(fn {{method, params}, id} ->
        %{"jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params}
      end)

    case Req.post(new(), json: body) do
      {:ok, %Req.Response{status: status, body: results}} when status in 200..299 and is_list(results) ->
        results
        |> Enum.sort_by(& &1["id"])
        |> Enum.map(&unwrap_result/1)

      {:ok, %Req.Response{status: status}} ->
        List.duplicate({:error, %Error{message: "HTTP #{status}"}}, length(calls))

      {:error, exception} ->
        err = {:error, %Error{message: "request failed: #{Exception.message(exception)}"}}
        List.duplicate(err, length(calls))
    end
  end

  defp new do
    config = Application.get_env(:ethercoaster, Ethercoaster.ExecutionChain, [])

    base_url = Process.get(@base_url_key) || Keyword.get(config, :base_url, "http://localhost:8545")
    receive_timeout = Keyword.get(config, :receive_timeout, 15_000)
    req_options = Keyword.get(config, :req_options, [])

    [base_url: base_url, receive_timeout: receive_timeout, finch: Ethercoaster.Finch]
    |> Keyword.merge(req_options)
    |> Req.new()
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}})
       when status in 200..299 do
    unwrap_result(body)
  end

  defp handle_response({:ok, %Req.Response{status: status}}) do
    {:error, %Error{message: "HTTP #{status}"}}
  end

  defp handle_response({:error, %Req.TransportError{reason: reason}}) do
    {:error, %Error{message: "transport error: #{inspect(reason)}"}}
  end

  defp handle_response({:error, exception}) do
    {:error, %Error{message: "request failed: #{Exception.message(exception)}"}}
  end

  defp unwrap_result(%{"result" => result}), do: {:ok, result}

  defp unwrap_result(%{"error" => %{"code" => code, "message" => message}}) do
    {:error, %Error{code: code, message: message}}
  end

  defp unwrap_result(_), do: {:error, %Error{message: "unexpected response format"}}
end
