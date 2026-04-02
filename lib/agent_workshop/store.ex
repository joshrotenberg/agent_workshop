defmodule AgentWorkshop.Store do
  @moduledoc """
  Shared key-value store for agent coordination.

  A scratchpad that agents and humans can read and write. Useful for
  sharing specs, coordination data, accumulated results, and runtime
  configuration across agents.

  The store is backed by ETS and survives agent resets (it's Workshop-level
  state, not per-agent). It does not survive Workshop restarts.

  ## From IEx

      import AgentWorkshop.Workshop

      put(:spec, "LRU cache with 1000 entries and 5 min TTL")
      get(:spec)
      keys()

  ## From agents (via MCP tools)

  Agents with MCP access can use `workshop_put`, `workshop_get`, `workshop_keys`.

  ## Namespacing

  Keys can be any term. Use tuples for namespacing:

      put({:impl, :notes}, "Chose GenServer over Agent for state")
      put({:spec, :cache}, "LRU with TTL support")
      keys()  # => [{:impl, :notes}, {:spec, :cache}]
  """

  @table :agent_workshop_store

  @doc """
  Put a value in the store.

  ## Examples

      Store.put(:spec, "Implement LRU cache")
      Store.put({:impl, :notes}, "Using GenServer")
  """
  @spec put(term(), term()) :: :ok
  def put(key, value) do
    ensure_table!()
    :ets.insert(@table, {key, value, System.monotonic_time()})
    AgentWorkshop.PubSub.broadcast({:store, :put, key})
    :ok
  end

  @doc """
  Get a value from the store. Returns `nil` if not found.
  """
  @spec get(term()) :: term() | nil
  def get(key) do
    ensure_table!()

    case :ets.lookup(@table, key) do
      [{^key, value, _ts}] -> value
      [] -> nil
    end
  end

  @doc """
  Get a value with a default if not found.
  """
  @spec get(term(), term()) :: term()
  def get(key, default) do
    get(key) || default
  end

  @doc """
  List all keys in the store.
  """
  @spec keys() :: [term()]
  def keys do
    ensure_table!()

    :ets.tab2list(@table)
    |> Enum.map(&elem(&1, 0))
    |> Enum.sort()
  end

  @doc """
  Delete a key from the store.
  """
  @spec delete(term()) :: :ok
  def delete(key) do
    ensure_table!()
    :ets.delete(@table, key)
    AgentWorkshop.PubSub.broadcast({:store, :delete, key})
    :ok
  end

  @doc """
  Clear all entries from the store.
  """
  @spec clear() :: :ok
  def clear do
    ensure_table!()
    :ets.delete_all_objects(@table)
    AgentWorkshop.PubSub.broadcast({:store, :clear})
    :ok
  end

  @doc """
  List all key-value pairs.
  """
  @spec entries() :: [{term(), term()}]
  def entries do
    ensure_table!()

    :ets.tab2list(@table)
    |> Enum.map(fn {key, value, _ts} -> {key, value} end)
    |> Enum.sort()
  end

  @doc false
  def table_name, do: @table

  @doc false
  def create_table do
    if :ets.info(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set])
    end
  end

  @doc false
  def delete_table do
    if :ets.info(@table) != :undefined do
      :ets.delete(@table)
    end
  end

  defp ensure_table! do
    if :ets.info(@table) == :undefined do
      raise "Workshop not started. Call configure/1 first."
    end
  end
end
