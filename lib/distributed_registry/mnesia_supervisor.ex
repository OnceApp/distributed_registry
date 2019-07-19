defmodule DistributedRegistry.MnesiaSupervisor do
  @moduledoc false
  use Elixir.Supervisor
  def start_link(pid), do: Elixir.Supervisor.start_link(__MODULE__, pid, name: __MODULE__)

  def init(pid) do
    children = [
      %{
        id: DistributedRegistry.MnesiaRegistry,
        start: {DistributedRegistry.MnesiaRegistry, :start_link, [[]]}
      },
      %{
        id: DistributedRegistry.Mnesia.Cluster,
        start: {DistributedRegistry.Mnesia.Cluster, :start_link, [pid]}
      }
    ]

    Elixir.Supervisor.init(children, strategy: :one_for_one)
  end
end
