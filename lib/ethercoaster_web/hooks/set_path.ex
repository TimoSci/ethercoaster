defmodule EthercoasterWeb.Hooks.SetPath do
  @moduledoc "LiveView on_mount hook that captures the current URI path."

  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

  def on_mount(:default, _params, _session, socket) do
    {:cont,
     attach_hook(socket, :set_path, :handle_params, fn _params, uri, socket ->
       {:cont, assign(socket, :current_path, URI.parse(uri).path)}
     end)}
  end
end
