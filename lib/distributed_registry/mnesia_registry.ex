defmodule DistributedRegistry.MnesiaRegistry do
  use GenServer

  @moduledoc """
  Registry implementation using mnesia as data store
  """

  require DistributedRegistry.MnesiaSchema.ProcessRegistry
  require Logger
  alias DistributedRegistry.MnesiaSchema.ProcessRegistry

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    {:ok, []}
  end

  def register_name(name, pid) do
    GenServer.call(__MODULE__, {:register_name, name, pid})
  end

  def whereis_name(name) do
    GenServer.call(__MODULE__, {:whereis_name, name})
  end

  def unregister_name(name) do
    GenServer.call(__MODULE__, {:unregister_name, name})
  end

  def send(name, message) do
    GenServer.call(__MODULE__, {:send, name, message})
  end

  @impl true
  def handle_call({:send, name, message}, from, state) do
    start_task(from, fn ->
      case lookup_for_process_in_mnesia(name) do
        :undefined ->
          :ok

        pid ->
          Kernel.send(pid, message)
      end
    end)

    {:noreply, state}
  end

  @impl true
  def handle_call({:unregister_name, name}, from, state) do
    start_task(from, fn -> do_unregister_name(name) end)
    {:noreply, state}
  end

  @impl true
  def handle_call({:whereis_name, name}, from, state) do
    start_task(from, fn -> lookup_for_process_in_mnesia(name) end)
    {:noreply, state}
  end

  @impl true
  def handle_call({:register_name, name, pid}, from, state) do
    start_task(
      from,
      fn ->
        transaction_result = :mnesia.transaction(fn -> insert_pid(name, pid) end)

        handle_transaction("register name #{inspect({name, pid})}", transaction_result, :no)
      end
    )

    {:noreply, state}
  end

  defp do_unregister_name(name) do
    result =
      :mnesia.transaction(fn ->
        :mnesia.delete({ProcessRegistry.table_name(), name})
      end)

    handle_transaction("remove name #{inspect(name)}", result, nil)
    :ok
  end

  defp handle_transaction(
         intent,
         {:aborted, {:no_exists, :process_registry} = reason},
         _default_response
       ) do
    Logger.error("Failed to #{intent}: #{inspect(reason)}\nStopping the process.")
    :init.stop()
  end

  defp handle_transaction(intent, {:aborted, reason}, default_response) do
    Logger.warn("Failed to #{intent}: #{inspect(reason)}")
    default_response
  end

  defp handle_transaction(intent, {:atomic, result}, _default_response) do
    Logger.debug(fn -> intent end)
    result
  end

  defp insert_pid(name, pid) do
    table_name = ProcessRegistry.table_name()

    case :mnesia.read(table_name, name) do
      [] ->
        :ok =
          :mnesia.write(ProcessRegistry.process_registry(name: name, pid: pid, node: node(pid)))

        DistributedRegistry.PidMonitor.start(name, pid)
        :yes

      [{^table_name, ^name, other_pid, _}] ->
        if pid_alive?(other_pid),
          do: :no,
          else: save_information_into_mnesia(name, pid)
    end
  end

  defp save_information_into_mnesia(name, pid) do
    :ok = :mnesia.write(ProcessRegistry.process_registry(name: name, pid: pid))
    DistributedRegistry.PidMonitor.start(name, pid)
    :yes
  end

  defp lookup_for_process_in_mnesia(name) do
    table_name = ProcessRegistry.table_name()
    case :mnesia.transaction(fn -> :mnesia.read(ProcessRegistry.table_name(), name) end) do
      {:atomic, []} ->
        :undefined

      {:atomic, [{^table_name, ^name, pid, _node}]} when is_pid(pid) ->
        ensure_process_alive(name, pid)

      {:atomic, results} ->
        Logger.warn(
          "Unexpected results from read in whereis_name(#{inspect(name)}): #{inspect(results)}"
        )

        :undefined

      {:aborted, reason} ->
        Logger.warn(
          "Failed to read mnesia table looking for #{inspect(name)}: #{inspect(reason)}"
        )

        :undefined
    end
  end

  defp ensure_process_alive(name, pid) do
    if pid_alive?(pid) do
      pid
    else
      do_unregister_name(name)
      :undefined
    end
  end

  defp pid_alive?(pid) do
    case :rpc.call(node(pid), Process, :alive?, [pid], 1_000) do
      {:badrpc, _reason} -> false
      alive? -> alive?
    end
  end

  defp start_task(from, callback),
    do:
      Task.Supervisor.start_child(DistributedRegistry.TaskSupervisor, fn ->
        GenServer.reply(from, callback.())
      end)

  @impl true
  def handle_info(message, state) do
    Logger.info("Unexpected message: #{inspect(message)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, _state) do
    Logger.info("Shutting down with reason: #{inspect(reason)}")
    :ok
  end
end
