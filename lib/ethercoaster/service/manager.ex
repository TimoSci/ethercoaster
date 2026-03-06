defmodule Ethercoaster.Service.Manager do
  use DynamicSupervisor

  alias Ethercoaster.Service.Worker

  # Worker module is defined in Task 4; suppress compile warnings for now
  @compile {:no_warn_undefined, Ethercoaster.Service.Worker}

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_service(service_id) do
    case Registry.lookup(Ethercoaster.ServiceRegistry, service_id) do
      [{_pid, _}] ->
        {:error, :already_running}

      [] ->
        DynamicSupervisor.start_child(__MODULE__, {Worker, service_id})
    end
  end

  def stop_service(service_id) do
    case Registry.lookup(Ethercoaster.ServiceRegistry, service_id) do
      [{pid, _}] ->
        Worker.pause(pid)
        :ok

      [] ->
        {:error, :not_running}
    end
  end

  def get_worker_pid(service_id) do
    case Registry.lookup(Ethercoaster.ServiceRegistry, service_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> :error
    end
  end

  def get_worker_state(service_id) do
    case get_worker_pid(service_id) do
      {:ok, pid} -> Worker.get_state(pid)
      :error -> nil
    end
  end
end
