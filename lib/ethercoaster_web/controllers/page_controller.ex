defmodule EthercoasterWeb.PageController do
  use EthercoasterWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
