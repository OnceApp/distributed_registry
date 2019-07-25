defmodule DistributedRegistry.Mnesia.SauronSupervisor do
  @moduledoc false
  require Logger

  def start_leader do
    :global.sync()
    {:ok, pid} = DistributedRegistry.GlobalSupervisor.monitor(DistributedRegistry.Mnesia.Sauron)

    Logger.info("Sauron started on #{inspect(node(pid))}")
    :ok
  end
end
