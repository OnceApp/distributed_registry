defmodule DistributedRegistry.Mnesia.Cluster do
  @moduledoc """
  FSM to bootstrap mnesia cluster.
  """
  alias DistributedRegistry.Mnesia.Sauron
  alias DistributedRegistry.Mnesia.SauronSupervisor
  alias DistributedRegistry.MnesiaSchema.ProcessRegistry
  use GenStateMachine, callback_mode: [:state_functions, :state_enter]
  require Logger
  @quorum Application.get_env(:distributed_registry, :quorum, 1)
  @healthcheck_timeout 30_000
  @max_failed_healthcheck 4
  @cluster_sync_timeout 1_000

  def start_link(application_pid),
    do: GenStateMachine.start_link(__MODULE__, application_pid, name: __MODULE__)

  defp bootstraped?(node),
    do: length(:rpc.call(node, :mnesia, :system_info, [:running_db_nodes])) >= @quorum

  @impl true
  def init(application_pid) do
    :mnesia.subscribe(:system)
    :net_kernel.monitor_nodes(true, node_type: :visible)
    Code.ensure_loaded(Logger)

    if Node.list() == [] and @quorum == 1 do
      SauronSupervisor.start_leader()
      Sauron.add_mnesia_node(Node.self())
      actions = [{:next_event, :internal, :notify}]
      {:ok, :running, application_pid, actions}
    else
      actions = [{:next_event, :internal, :check_quorum}]
      {:ok, :starting, application_pid, actions}
    end
  end

  def starting(:internal, :check_quorum, application_pid) do
    if check_quorum() do
      case Enum.find(Node.list(), &bootstraped?/1) do
        nil ->
          actions = [{:next_event, :internal, :elect}]
          {:next_state, :seed_election, application_pid, actions}

        _node ->
          :global.sync()
          add_node(application_pid)
      end
    else
      {:next_state, :waiting_for_quorum, application_pid}
    end
  end

  def starting(event_type, event_content, data) do
    handle_event(event_type, event_content, :starting, data)
  end

  defp add_node(application_pid) do
    try do
      Sauron.add_mnesia_node(Node.self())
      actions = [{:next_event, :internal, :sync}]
      {:next_state, :wait_for_table_replicas, application_pid, actions}
    rescue
      _ ->
        actions = [{:next_event, :internal, :check_quorum}]
        {:ok, :starting, application_pid, actions}
    end
  end

  def waiting_for_quorum(:info, {:nodeup, _node, _}, application_pid) do
    actions = [{:next_event, :internal, :check_quorum}]
    {:next_state, :starting, application_pid, actions}
  end

  def waiting_for_quorum(event_type, event_content, data) do
    handle_event(event_type, event_content, :waiting_for_quorum, data)
  end

  def seed_election(:internal, :elect, application_pid) do
    SauronSupervisor.start_leader()
    Sauron.add_mnesia_node(Node.self())
    actions = [{:next_event, :internal, :sync}]
    {:next_state, :wait_for_table_replicas, application_pid, actions}
  end

  def seed_election(event_type, event_content, data) do
    handle_event(event_type, event_content, :seed_election, data)
  end

  def wait_for_table_replicas(:internal, :sync, application_pid),
    do: check_if_added_to_cluster_and_transition(application_pid)

  def wait_for_table_replicas({:timeout, :cluster_sync}, :sync, application_pid),
    do: check_if_added_to_cluster_and_transition(application_pid)

  def wait_for_table_replicas(:info, {:nodeup, _node, _}, _application_pid) do
    :keep_state_and_data
  end

  def wait_for_table_replicas(
        :info,
        {:mnesia_system_event, {:mnesia_up, _node}},
        _application_pid
      ),
      do: :keep_state_and_data

  def wait_for_table_replicas(event_type, event_content, data) do
    handle_event(event_type, event_content, :wait_for_table_replicas, data)
  end

  defp check_if_added_to_cluster_and_transition(application_pid) do
    if node_in_process_registry_replicas() and healthy?(health_metrics()) do
      SauronSupervisor.start_leader()
      to_running(application_pid)
    else
      schedule_cluster_sync_timeout()
    end
  end

  defp node_in_process_registry_replicas do
    case :mnesia.transaction(fn ->
           :mnesia.table_info(ProcessRegistry.table_name(), :active_replicas)
         end) do
      {:aborted, _} -> false
      {:atomic, replicas} -> Node.self() in replicas
    end
  end

  defp to_running(application_pid) do
    actions = [{:next_event, :internal, :notify}]
    {:next_state, :running, application_pid, actions}
  end

  defp schedule_cluster_sync_timeout do
    actions = [{{:timeout, :cluster_sync}, @cluster_sync_timeout, :sync}]
    {:keep_state_and_data, actions}
  end

  def running(:internal, :notify, application_pid) do
    notify_quorum(application_pid)
    actions = [{{:timeout, :healthcheck}, @healthcheck_timeout, %{nb_unhealthy: 0}}]
    {:keep_state_and_data, actions}
  end

  def running(:info, {:nodeup, _node, _}, _application_pid), do: :keep_state_and_data

  def running(:info, {:mnesia_system_event, {:mnesia_up, _node}}, _application_pid) do
    :keep_state_and_data
  end

  def running(:info, {:mnesia_system_event, {:mnesia_down, _node}}, _application_pid),
    do: :keep_state_and_data

  def running({:timeout, :healthcheck}, %{nb_unhealthy: nb_unhealthy}, _application_pid) do
    health_metrics = health_metrics()

    case healthy?(health_metrics) do
      true ->
        actions = [{{:timeout, :healthcheck}, @healthcheck_timeout, %{nb_unhealthy: 0}}]
        {:keep_state_and_data, actions}

      false ->
        if nb_unhealthy >= @max_failed_healthcheck - 1 do
          Logger.error(
            "Mnesia process registry has been unhealthy too many times (#{nb_unhealthy + 1}). Stopping process."
          )

          :init.stop()
        else
          Logger.warn(
            "Mnesia process registry is healthcheck failed #{nb_unhealthy + 1} times.\n#{
              inspect(health_metrics)
            }"
          )

          actions = [
            {{:timeout, :healthcheck}, @healthcheck_timeout, %{nb_unhealthy: nb_unhealthy + 1}}
          ]

          {:keep_state_and_data, actions}
        end
    end
  end

  def running(event_type, event_content, data) do
    handle_event(event_type, event_content, :running, data)
  end

  defp health_metrics do
    nb_mnesia_nodes = :mnesia.system_info(:running_db_nodes) |> length()
    nb_table_nodes = length(table_replicas())
    nb_nodes = length(Node.list([:visible, :this]))
    %{nb_mnesia_nodes: nb_mnesia_nodes, nb_table_nodes: nb_table_nodes, nb_nodes: nb_nodes}
  end

  defp table_replicas do
    case :mnesia.transaction(fn ->
           :mnesia.table_info(ProcessRegistry.table_name(), :active_replicas)
         end) do
      {:aborted, reason} ->
        Logger.error(
          "Failed to get number of replica for table #{inspect(ProcessRegistry.table_name())}: #{
            inspect(reason)
          }. Stopping the process"
        )

        :init.stop()

      {:atomic, replicas} ->
        replicas
    end
  end

  defp healthy?(%{
         nb_mnesia_nodes: nb_mnesia_nodes,
         nb_table_nodes: nb_table_nodes,
         nb_nodes: _nb_nodes
       }),
       do: nb_mnesia_nodes == nb_table_nodes and nb_mnesia_nodes >= @quorum

  @impl true
  def handle_event(:info, {:nodeup, _new_node, _}, _state, _data) do
    :keep_state_and_data
  end

  @impl true
  def handle_event(:info, {:nodedown, _new_node, _}, _state, _application_pid) do
    :keep_state_and_data
  end

  def handle_event(:enter, from, to, data) do
    msg = "FSM #{inspect(data)} transitionned from #{from} to #{to}"
    Logger.info(msg)
    :keep_state_and_data
  end

  @impl true
  def handle_event(event_type, event_content, state, data) do
    msg =
      "Receive unexpected message: #{inspect(event_type)}, #{inspect(event_content)},#{
        inspect(state)
      }, #{inspect(data)}"

    Logger.warn(msg)

    :keep_state_and_data
  end

  defp notify_quorum(pid) do
    send(pid, :quorum)
  end

  defp check_quorum, do: length(Node.list([:visible, :this])) >= @quorum
  @impl true
  def terminate(reason, _state, _data) do
    Logger.info("Terminated: #{inspect(reason)}")
    :ok
  end
end
