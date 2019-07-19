defmodule DistributedRegistry.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false
  @local_env [:test, :local]
  use Application
  require Logger

  def start(_type, args) do
    Logger.info("Starting distributed registry")
    current_env = env(args)
    # List all child processes to be supervised
    children = [
      {Cluster.Supervisor,
       [topologies(current_env), [name: DistributedRegistry.ClusterSupervisor]]},
      {Task.Supervisor, name: DistributedRegistry.TaskSupervisor},
      %{
        id: DistributedRegistry.GlobalSupervisor,
        start: {DistributedRegistry.GlobalSupervisor, :start_link, []}
      },
      %{
        id: DistributedRegistry.MnesiaSupervisor,
        start: {DistributedRegistry.MnesiaSupervisor, :start_link, [self()]}
      }
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: DistributedRegistry.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def start_phase(_what, _, _) do
    receive do
      :quorum ->
        Logger.info("Distributed registry started")
        :ok
    after
      60_000 -> {:error, :cluster_timedout}
    end
  end

  defp env(args), do: hd(args)

  defp topologies(env) when env in @local_env,
    do: [
      cluster: [
        strategy: Cluster.Strategy.Epmd,
        connect: {__MODULE__, :connect_node, []},
        config: [hosts: [Node.self()]]
      ]
    ]

  defp topologies(_env),
    do: [
      cluster: [
        strategy: ClusterEC2.Strategy.Tags,
        connect: {__MODULE__, :connect_node, []},
        config: Application.fetch_env!(:distributed_registry, :libcluster_ec2_config)
      ]
    ]

  def connect_node(node) do
    case :net_kernel.connect_node(node) do
      true ->
        :global.sync()
        true

      false ->
        false
    end
  end
end
