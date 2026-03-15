defmodule EthercoasterWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use EthercoasterWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  Used as the inner layout for all pages (except the home page).
  Includes navbar, breadcrumb navigation, flash messages, and main content area.
  """
  attr :flash, :map, default: %{}, doc: "the map of flash messages"
  attr :current_path, :string, default: "/", doc: "the current request path"

  def app(assigns) do
    ~H"""
    <header class="navbar px-4 sm:px-6 lg:px-8">
      <div class="flex-1">
        <a href="/" class="flex-1 flex w-fit items-center gap-2">
          <img src={~p"/images/logo.svg"} width="36" />
          <span class="text-sm font-semibold">v{Application.spec(:phoenix, :vsn)}</span>
        </a>
      </div>
      <div class="flex-none">
        <ul class="flex flex-column px-1 space-x-4 items-center">
          <li>
            <a href="/services" class="btn btn-ghost">Services</a>
          </li>
          <li>
            <a href="/validators/query" class="btn btn-ghost">Query</a>
          </li>
          <li>
            <.theme_toggle />
          </li>
        </ul>
      </div>
    </header>

    <.breadcrumbs path={@current_path} />

    <main class="px-4 py-4 sm:px-6 lg:px-8">
      <div class={["mx-auto space-y-4", !assigns[:full_width] && "max-w-5xl"]}>
        {@inner_content}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Renders breadcrumb navigation from the current URL path.

  Generates hierarchical links like "Home > Services > Progress Map"
  based on the URL path segments.
  """
  attr :path, :string, required: true

  def breadcrumbs(assigns) do
    segments =
      assigns.path
      |> String.trim_leading("/")
      |> String.split("/", trim: true)
      |> Enum.reject(&dynamic_segment?/1)

    crumbs =
      segments
      |> Enum.with_index()
      |> Enum.map(fn {segment, index} ->
        href = "/" <> Enum.join(Enum.take(segments, index + 1), "/")
        %{label: segment_label(segment), href: href}
      end)

    assigns = assign(assigns, :crumbs, crumbs)

    ~H"""
    <nav class="breadcrumbs px-4 sm:px-6 lg:px-8 text-sm">
      <ul>
        <li :if={@crumbs != []}>
          <a href="/">Home</a>
        </li>
        <li :for={crumb <- @crumbs}>
          <a href={crumb.href}>{crumb.label}</a>
        </li>
      </ul>
    </nav>
    """
  end

  defp dynamic_segment?(segment), do: String.match?(segment, ~r/^\d+$/)

  defp segment_label("progress_map"), do: "Progress Map"
  defp segment_label("transaction_types"), do: "Transaction Types"

  defp segment_label(segment) do
    segment
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
