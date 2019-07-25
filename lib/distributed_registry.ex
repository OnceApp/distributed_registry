defmodule DistributedRegistry do
  @moduledoc """
  Documentation for DistributedRegistry.
  """

  # @spec register_name(term(), pid()) :: true | {false, pid() | :undefined}
  defdelegate register_name(name, pid), to: DistributedRegistry.MnesiaRegistry

  @spec whereis_name(term()) :: pid() | :undefined
  defdelegate whereis_name(name), to: DistributedRegistry.MnesiaRegistry

  @spec unregister_name(term()) :: :ok
  defdelegate unregister_name(name), to: DistributedRegistry.MnesiaRegistry

  @spec send(term(), term()) :: :ok
  # cast
  defdelegate send(name, message), to: DistributedRegistry.MnesiaRegistry
end
