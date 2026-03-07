defmodule EthercoasterWeb.ValidatorsLive do
  use EthercoasterWeb, :live_view

  alias Ethercoaster.Validators
  alias Ethercoaster.ValidatorImport

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:validators, Validators.list_validators())
      |> assign(:editing_id, nil)
      |> assign(:form_public_key, "")
      |> assign(:form_index, "")
      |> assign(:form_error, nil)
      |> assign(:upload_error, nil)
      |> allow_upload(:validator_file, accept: ~w(.csv .json), max_entries: 1)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Validators
      <:subtitle>Manage saved validator records.</:subtitle>
    </.header>

    <div class="mt-6">
      <div class="card bg-base-200 p-6 mb-6">
        <h3 class="text-lg font-semibold mb-4">
          {if @editing_id, do: "Edit Validator", else: "Add Validator"}
        </h3>
        <form phx-submit="save" phx-change="validate_upload" class="flex gap-2 items-end flex-wrap">
          <div class="flex-1 min-w-48">
            <label class="label">Public Key</label>
            <input
              type="text"
              name="public_key"
              value={@form_public_key}
              class="input input-bordered w-full"
              placeholder="0x..."
            />
          </div>
          <div class="w-32">
            <label class="label">Index</label>
            <input
              type="number"
              name="index"
              value={@form_index}
              class="input input-bordered w-full"
              min="0"
              placeholder="0"
            />
          </div>
          <button type="submit" class="btn btn-primary">
            <.icon name={if @editing_id, do: "hero-check", else: "hero-plus"} class="size-4" />
            {if @editing_id, do: "Update", else: "Add"}
          </button>
          <button :if={@editing_id} type="button" phx-click="cancel_edit" class="btn btn-ghost">
            Cancel
          </button>
        </form>
        <p :if={@form_error} class="text-error text-sm mt-2">{@form_error}</p>

        <div class="divider">or import from file</div>

        <div class="flex gap-2 items-center flex-wrap">
          <.live_file_input upload={@uploads.validator_file} class="file-input file-input-bordered file-input-sm" />
          <button type="button" phx-click="upload_validators" class="btn btn-soft btn-sm">
            <.icon name="hero-arrow-up-tray" class="size-4" /> Import
          </button>
          <span class="text-xs opacity-60">CSV or JSON file with public keys or indices</span>
        </div>
        <p :if={@upload_error} class="text-error text-sm mt-2">{@upload_error}</p>
      </div>

      <div class="overflow-x-auto">
        <table class="table table-zebra w-full">
          <thead>
            <tr>
              <th>Index</th>
              <th>Public Key</th>
              <th>Created</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr :if={@validators == []}>
              <td colspan="4" class="text-center opacity-50">No validators saved yet.</td>
            </tr>
            <tr :for={v <- @validators}>
              <td>{v.index}</td>
              <td class="font-mono text-sm max-w-xs truncate">{v.public_key}</td>
              <td class="text-sm opacity-70">{Calendar.strftime(v.inserted_at, "%Y-%m-%d %H:%M")}</td>
              <td class="flex gap-1">
                <button phx-click="edit" phx-value-id={v.id} class="btn btn-ghost btn-sm">
                  <.icon name="hero-pencil-square" class="size-4" />
                </button>
                <button
                  phx-click="delete"
                  phx-value-id={v.id}
                  data-confirm="Delete this validator?"
                  class="btn btn-ghost btn-sm text-error"
                >
                  <.icon name="hero-trash" class="size-4" />
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("save", %{"public_key" => public_key, "index" => index}, socket) do
    attrs = %{
      public_key: String.trim(public_key),
      index: parse_int(index)
    }

    result =
      if socket.assigns.editing_id do
        validator = Validators.get_validator!(socket.assigns.editing_id)
        Validators.update_validator(validator, attrs)
      else
        Validators.create_validator(attrs)
      end

    case result do
      {:ok, _} ->
        socket =
          socket
          |> assign(:validators, Validators.list_validators())
          |> assign(:editing_id, nil)
          |> assign(:form_public_key, "")
          |> assign(:form_index, "")
          |> assign(:form_error, nil)

        {:noreply, socket}

      {:error, changeset} ->
        error =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end) |> inspect()

        {:noreply, assign(socket, :form_error, "Validation failed: #{error}")}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    validator = Validators.get_validator!(String.to_integer(id))

    socket =
      socket
      |> assign(:editing_id, validator.id)
      |> assign(:form_public_key, validator.public_key)
      |> assign(:form_index, Integer.to_string(validator.index))
      |> assign(:form_error, nil)

    {:noreply, socket}
  end

  def handle_event("cancel_edit", _, socket) do
    socket =
      socket
      |> assign(:editing_id, nil)
      |> assign(:form_public_key, "")
      |> assign(:form_index, "")
      |> assign(:form_error, nil)

    {:noreply, socket}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    Validators.delete_validator(String.to_integer(id))
    {:noreply, assign(socket, :validators, Validators.list_validators())}
  end

  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("upload_validators", _params, socket) do
    uploaded =
      consume_uploaded_entries(socket, :validator_file, fn %{path: path}, entry ->
        content = File.read!(path)
        {:ok, ValidatorImport.parse_file(content, entry.client_name)}
      end)

    case uploaded do
      [{:ok, parsed}] ->
        try do
          Validators.resolve_inputs(parsed)

          socket =
            socket
            |> assign(:validators, Validators.list_validators())
            |> assign(:upload_error, nil)
            |> put_flash(:info, "Imported #{length(parsed)} validator(s)")

          {:noreply, socket}
        rescue
          e ->
            {:noreply, assign(socket, :upload_error, Exception.message(e))}
        end

      [{:error, reason}] ->
        {:noreply, assign(socket, :upload_error, reason)}

      _ ->
        {:noreply, socket}
    end
  end

  defp parse_int(""), do: nil

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> n
      _ -> nil
    end
  end
end
