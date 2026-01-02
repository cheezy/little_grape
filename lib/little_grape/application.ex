defmodule LittleGrape.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      LittleGrapeWeb.Telemetry,
      LittleGrape.Repo,
      {DNSCluster, query: Application.get_env(:little_grape, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: LittleGrape.PubSub},
      # Start a worker by calling: LittleGrape.Worker.start_link(arg)
      # {LittleGrape.Worker, arg},
      # Start to serve requests, typically the last entry
      LittleGrapeWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: LittleGrape.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    LittleGrapeWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
