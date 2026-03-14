defmodule Ethercoaster.ExecutionChain.Error do
  @moduledoc """
  Exception struct for execution layer JSON-RPC errors.
  """

  defexception [:code, :message]

  @type t :: %__MODULE__{
          code: integer() | nil,
          message: String.t()
        }

  @impl true
  def message(%__MODULE__{message: message}), do: message
end
