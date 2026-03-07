defmodule EthercoasterWeb.TransactionTypesLive do
  use EthercoasterWeb, :live_view

  import Ecto.Query

  alias Ethercoaster.Repo
  alias Ethercoaster.TransactionType

  @impl true
  def mount(_params, _session, socket) do
    types =
      TransactionType
      |> preload([:category, :event])
      |> order_by([t], [asc: t.category_id, asc: t.name])
      |> Repo.all()

    {:ok, assign(socket, :types, types)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Transaction Types
      <:subtitle>All supported transaction types across consensus and execution layers.</:subtitle>
    </.header>

    <div class="mt-6">
      <button onclick="history.back()" class="btn btn-ghost btn-sm mb-4">
        <.icon name="hero-arrow-left" class="size-4" /> Back
      </button>

      <div class="overflow-x-auto">
        <table class="table table-zebra w-full">
          <thead>
            <tr>
              <th>Name</th>
              <th>Event</th>
              <th>Category</th>
              <th>Chain</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={type <- @types}>
              <td>{type.name}</td>
              <td>{type.event.name}</td>
              <td><span class="badge badge-sm">{type.category.name}</span></td>
              <td><span class={chain_badge(type.chain)}>{type.chain}</span></td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp chain_badge(:consensus), do: "badge badge-sm badge-primary"
  defp chain_badge(:execution), do: "badge badge-sm badge-secondary"
  defp chain_badge(_), do: "badge badge-sm"
end
