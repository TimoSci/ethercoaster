defmodule EthercoasterWeb.ReportsLive do
  use EthercoasterWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Financial Report
      <:subtitle>Transaction value reports coming soon.</:subtitle>
    </.header>
    """
  end
end
