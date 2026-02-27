defmodule Ethercoaster.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    beacon_config = Application.get_env(:ethercoaster, Ethercoaster.BeaconChain, [])

    children =
      [
        EthercoasterWeb.Telemetry,
        Ethercoaster.Repo,
        {DNSCluster, query: Application.get_env(:ethercoaster, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Ethercoaster.PubSub},
        if(beacon_config[:events_enabled],
          do:
            {Ethercoaster.BeaconChain.Events.Listener,
             topics: beacon_config[:events_topics] || []}
        ),
        # Start to serve requests, typically the last entry
        EthercoasterWeb.Endpoint
      ]
      |> Enum.reject(&is_nil/1)

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Ethercoaster.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    EthercoasterWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
