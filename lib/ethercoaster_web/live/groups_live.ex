defmodule EthercoasterWeb.GroupsLive do
  use EthercoasterWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Validator Groups
      <:subtitle>Group management coming soon.</:subtitle>
    </.header>
    """
  end
end
