defmodule EthercoasterWeb.ServiceLiveTest do
  use EthercoasterWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "mount" do
    test "renders the services page", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/services")
      assert html =~ "Services"
      assert html =~ "Create Service"
    end
  end
end
