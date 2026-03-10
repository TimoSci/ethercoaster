defmodule Ethercoaster.BeaconChain.Client do
  @moduledoc """
  Shared HTTP client for the Beacon Chain REST API.

  Builds a `Req.Request` from application config and provides `get/2` and `post/3`
  helpers that automatically extract the `"data"` key from responses.
  """

  alias Ethercoaster.BeaconChain.Error

  @base_url_key :beacon_chain_base_url

  @doc """
  Sets a per-process base URL override for beacon chain API calls.

  This is used by the service worker to direct requests to a service-specific
  endpoint. The override applies only to the current process.
  """
  def put_base_url(nil), do: :ok
  def put_base_url(url), do: Process.put(@base_url_key, url)

  @doc """
  Returns the current per-process base URL override, or nil.
  """
  def get_base_url, do: Process.get(@base_url_key)

  @doc """
  Builds a new `Req.Request` from application config.

  If a per-process base URL has been set via `put_base_url/1`, it takes
  precedence over the application config.

  Config keys (under `config :ethercoaster, Ethercoaster.BeaconChain`):
    * `:base_url` — Beacon node URL (default `"http://localhost:5052"`)
    * `:api_key` — optional bearer token for authenticated endpoints
    * `:receive_timeout` — HTTP receive timeout in ms (default `15_000`)
    * `:req_options` — additional options passed to `Req.new/1`
  """
  @spec new() :: Req.Request.t()
  def new do
    config = Application.get_env(:ethercoaster, Ethercoaster.BeaconChain, [])

    base_url = Process.get(@base_url_key) || Keyword.get(config, :base_url, "http://localhost:5052")
    api_key = Keyword.get(config, :api_key)
    receive_timeout = Keyword.get(config, :receive_timeout, 15_000)
    req_options = Keyword.get(config, :req_options, [])

    headers = if api_key, do: [{"authorization", "Bearer #{api_key}"}], else: []

    [base_url: base_url, headers: headers, receive_timeout: receive_timeout, finch: Ethercoaster.Finch]
    |> Keyword.merge(req_options)
    |> Req.new()
  end

  @doc """
  Makes a GET request to the given path.

  Returns `{:ok, data}` where `data` is the value under the `"data"` key in the
  response body, or `{:error, %Error{}}` on failure.
  """
  @spec get(String.t(), keyword()) :: {:ok, term()} | {:error, Error.t()}
  def get(path, params \\ []) do
    new()
    |> Req.get(url: path, params: params)
    |> handle_response()
  end

  @doc """
  Makes a POST request to the given path with a JSON body.

  Returns `{:ok, data}` where `data` is the value under the `"data"` key in the
  response body, or `{:error, %Error{}}` on failure.
  """
  @spec post(String.t(), term(), keyword()) :: {:ok, term()} | {:error, Error.t()}
  def post(path, body, params \\ []) do
    new()
    |> Req.post(url: path, json: body, params: params)
    |> handle_response()
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}})
       when status in 200..299 do
    case body do
      %{"data" => data} -> {:ok, data}
      data -> {:ok, data}
    end
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}})
       when is_map(body) do
    {:error,
     %Error{
       status: status,
       code: body["code"],
       message: body["message"] || "HTTP #{status}"
     }}
  end

  defp handle_response({:ok, %Req.Response{status: status}}) do
    {:error, %Error{status: status, message: "HTTP #{status}"}}
  end

  defp handle_response({:error, %Req.TransportError{reason: reason}}) do
    {:error, %Error{message: "transport error: #{inspect(reason)}"}}
  end

  defp handle_response({:error, exception}) do
    {:error, %Error{message: "request failed: #{Exception.message(exception)}"}}
  end
end
