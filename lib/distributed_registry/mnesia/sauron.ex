defmodule DistributedRegistry.Mnesia.Sauron do
  @moduledoc false
  alias DistributedRegistry.MnesiaSchema.ProcessRegistry
  use GenServer
  require Logger

  def init(_), do: {:ok, []}
  def add_mnesia_node(node), do: GenServer.call({:global, __MODULE__}, {:add_node, node})

  def handle_info(message, state) do
    Logger.warn("Unhandled message in leader: #{inspect(message)}")
    {:noreply, state}
  end

  def terminate(reason, _state) do
    Logger.warn("Terminiate leader: #{inspect(reason)}")
    :ok
  end

  def handle_call({:add_node, node}, _from, state) do
    log(ProcessRegistry.create_table(), "[Create table]")

    if node_added?(node) do
      log(:mnesia.change_config(:extra_db_nodes, [node]), "[Change config]")

      log(
        :mnesia.add_table_copy(ProcessRegistry.table_name(), node, :ram_copies),
        "[Add table copy]"
      )
    else
      Logger.info("[Sauron] - Node: #{inspect(node)} already in cluster")
    end

    {:reply, :ok, state}
  end

  defp node_added?(node) do
    case :mnesia.transaction(fn ->
           :mnesia.table_info(ProcessRegistry.table_name(), :active_replicas)
         end) do
      {:aborted, _} -> false
      {:atomic, replicas} -> not (node in replicas)
    end
  end

  defp log({:aborted, reason}, context),
    do: Logger.info("[Sauron] #{context} - Adding node failed: #{inspect(reason)}")

  defp log(_result, _context), do: nil
end
