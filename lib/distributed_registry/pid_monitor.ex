defmodule DistributedRegistry.PidMonitor do
  use GenServer
  @moduledoc "Start a process to update registry when registered process dies."

  @doc """
    The use of start is on purpose. We don't want the registry to link
    on the processes it registers. Otherwise, the registry will die with
    the first process it registered dies.
  """
  def start(name, pid) do
    GenServer.start(__MODULE__, name: name, pid: pid)
  end

  @impl true
  def init(name: name, pid: pid) do
    ref = Process.monitor(pid)
    {:ok, {ref, name, pid}}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, _reason}, {ref, name, pid} = state) do
    DistributedRegistry.MnesiaRegistry.unregister_name(name)
    {:stop, :normal, state}
  end

  @impl true
  def terminate(_reason, {ref, _name, _pid}) do
    Process.demonitor(ref)
    :ok
  end
end
