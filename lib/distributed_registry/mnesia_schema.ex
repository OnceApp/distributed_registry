defmodule DistributedRegistry.MnesiaSchema do
  require Record

  @moduledoc "Tables stored in mnesia"

  defmodule ProcessRegistry do
    @moduledoc "Table storing pids"

    Record.defrecord(:process_registry, [:name, :pid, :node])
    def fields, do: [:name, :pid, :node]
    def table_name, do: :process_registry
    @spec create_table() :: {:atomic, :ok} | {:aborted, term()}
    def create_table,
      do:
        :mnesia.create_table(table_name(), [
          {:attributes, fields()},
          {:ram_copies, [node()]}
        ])
  end
end
