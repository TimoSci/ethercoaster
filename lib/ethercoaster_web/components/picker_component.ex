defmodule EthercoasterWeb.PickerComponent do
  @moduledoc """
  Reusable picker component for selecting items from a paginated list.
  Used by service forms and transaction filters.
  """
  use EthercoasterWeb, :html

  @picker_size 5

  def picker_size, do: @picker_size

  attr :items, :list, required: true, doc: "list of {value, display} tuples"
  attr :label, :string, required: true
  attr :picker, :string, required: true
  attr :pick_event, :string, required: true
  attr :show, :boolean, required: true
  attr :offset, :integer, required: true
  attr :target, :any, default: nil
  attr :empty_message, :string, default: "No more items."

  def picker(assigns) do
    visible = Enum.slice(assigns.items, assigns.offset, @picker_size)
    has_more = length(assigns.items) > assigns.offset + @picker_size
    assigns = assign(assigns, visible: visible, has_more: has_more)

    ~H"""
    <div>
      <button
        type="button"
        phx-click="toggle_picker"
        phx-value-picker={@picker}
        phx-target={@target}
        class="btn btn-soft btn-sm mb-2 w-full"
      >
        <.icon name={if @show, do: "hero-chevron-up", else: "hero-chevron-down"} class="size-4" />
        {@label}
      </button>
      <div :if={@show} class="bg-base-300 rounded-lg p-2 space-y-1">
        <div
          :for={{value, display} <- @visible}
          class="flex items-center justify-between bg-base-100 rounded px-2 py-1"
        >
          <span class="font-mono text-sm truncate" title={value}>
            {display}
          </span>
          <button
            type="button"
            phx-click={@pick_event}
            phx-value-item={value}
            phx-target={@target}
            class="btn btn-ghost btn-xs text-success"
            title="Select"
          >
            <.icon name="hero-arrow-left" class="size-4" />
          </button>
        </div>
        <div :if={@visible == []} class="text-xs opacity-50 text-center py-2">
          {@empty_message}
        </div>
        <div class="flex justify-between mt-1">
          <button
            type="button"
            phx-click="picker_prev"
            phx-value-picker={@picker}
            phx-target={@target}
            class="btn btn-ghost btn-xs"
            disabled={@offset == 0}
          >
            <.icon name="hero-chevron-up" class="size-3" /> Prev
          </button>
          <button
            type="button"
            phx-click="picker_next"
            phx-value-picker={@picker}
            phx-target={@target}
            class="btn btn-ghost btn-xs"
            disabled={not @has_more}
          >
            Next <.icon name="hero-chevron-down" class="size-3" />
          </button>
        </div>
      </div>
    </div>
    """
  end
end
