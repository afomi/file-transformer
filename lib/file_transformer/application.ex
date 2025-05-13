defmodule FileTransformer.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      FileTransformerWeb.Telemetry,
      # FileTransformer.Repo,
      {DNSCluster, query: Application.get_env(:file_transformer, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: FileTransformer.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: FileTransformer.Finch},
      # Start a worker by calling: FileTransformer.Worker.start_link(arg)
      # {FileTransformer.Worker, arg},
      # Start to serve requests, typically the last entry
      FileTransformerWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: FileTransformer.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    FileTransformerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
