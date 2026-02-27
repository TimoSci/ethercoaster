defmodule Ethercoaster.BeaconChain.Error do
  @moduledoc """
  Exception struct for Beacon Chain API errors.

  Supports both `{:error, %Error{}}` pattern matching and `raise %Error{}`.
  """

  defexception [:status, :code, :message]

  @type t :: %__MODULE__{
          status: integer() | nil,
          code: integer() | nil,
          message: String.t()
        }

  @impl true
  def message(%__MODULE__{message: message}), do: message
end
