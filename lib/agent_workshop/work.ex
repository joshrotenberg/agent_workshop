defmodule AgentWorkshop.Work do
  @moduledoc """
  Work board for agent coordination.

  A structured task tracker where work items flow through a lifecycle.
  Agents poll for work matching their role, claim it, and advance it
  through states. Dependencies between items handle ordering.

  ## Work item lifecycle

      new → ready → claimed → in_progress → done
                                           → failed
                         ↑
                   blocked (unmet dependency)
                   cancelled

  ## Usage from IEx

      import AgentWorkshop.Workshop

      # Add work
      work(:cache, "Implement LRU cache",
        type: :code, spec: "LRU with 1000 entries and TTL")
      work(:cache_review, "Review cache implementation",
        type: :review, depends_on: [:cache])
      work(:cache_tests, "Write cache tests",
        type: :test, depends_on: [:cache])

      # Browse
      board()                    # full board
      board(status: :ready)      # items ready to pick up
      board(type: :code)         # only code tasks

      # Work on items
      claim(:cache, :impl)      # agent claims the task
      start_work(:cache)        # mark in progress
      complete(:cache)          # mark done, unblocks dependents
      fail(:cache, "tests broke")

  ## Agent polling

  Agents check the board for work matching their type:

      every(:coder, "Check board(type: :code, status: :ready) and work on one item",
        interval: :timer.minutes(2))
  """

  alias AgentWorkshop.{PubSub, Telemetry}

  @table :agent_workshop_work

  # Lifecycle states:
  #   :new         -- just added; has unmet dependencies, waiting for them
  #   :ready       -- all dependencies satisfied (or none); available for claim
  #   :claimed     -- an agent has claimed this item but hasn't started yet
  #   :in_progress -- actively being worked on
  #   :done        -- completed successfully; unblocks downstream dependents
  #   :failed      -- execution failed; blocks downstream dependents
  #   :blocked     -- a dependency failed or was cancelled
  #   :cancelled   -- manually cancelled; blocks downstream dependents
  #
  # Dependency resolution: when an item completes (:done), all items that
  # depend on it are re-evaluated. If all their dependencies are now :done,
  # they transition from :new/:blocked to :ready. When an item fails or is
  # cancelled, its dependents move to :blocked.
  @valid_statuses [:new, :ready, :claimed, :in_progress, :done, :failed, :blocked, :cancelled]
  @valid_types [:code, :review, :test, :docs, :deploy, :triage, :custom]

  defstruct [
    :id,
    :title,
    :spec,
    :type,
    :claimed_by,
    :result,
    :error,
    :created_at,
    :claimed_at,
    :started_at,
    :completed_at,
    status: :new,
    priority: 3,
    depends_on: []
  ]

  @type t :: %__MODULE__{
          id: atom(),
          title: String.t(),
          spec: String.t() | nil,
          type: atom(),
          status: atom(),
          priority: non_neg_integer(),
          depends_on: [atom()],
          claimed_by: atom() | nil,
          result: String.t() | nil,
          error: String.t() | nil,
          created_at: DateTime.t(),
          claimed_at: DateTime.t() | nil,
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil
        }

  # ── Table management ────────────────────────────────────────

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

  # ── CRUD ────────────────────────────────────────────────────

  @doc """
  Add a work item to the board.
  """
  @spec add(atom(), String.t(), keyword()) :: :ok
  def add(id, title, opts \\ []) do
    type = Keyword.get(opts, :type, :custom)
    spec = Keyword.get(opts, :spec)
    priority = Keyword.get(opts, :priority, 3)
    depends_on = Keyword.get(opts, :depends_on, [])

    item = %__MODULE__{
      id: id,
      title: title,
      spec: spec,
      type: type,
      priority: priority,
      depends_on: depends_on,
      created_at: DateTime.utc_now()
    }

    # Set initial status based on dependencies
    item = resolve_status(item)

    :ets.insert(@table, {id, item})
    Telemetry.event(:work_added, %{}, %{id: id, type: type})
    PubSub.broadcast({:work, :added, id})
    :ok
  end

  @doc """
  Get a work item by ID.
  """
  @spec get(atom()) :: t() | nil
  def get(id) do
    case :ets.lookup(@table, id) do
      [{^id, item}] -> item
      [] -> nil
    end
  end

  @doc """
  List work items, optionally filtered.
  """
  @spec list(keyword()) :: [t()]
  def list(filters \\ []) do
    :ets.tab2list(@table)
    |> Enum.map(&elem(&1, 1))
    |> apply_filters(filters)
    |> Enum.sort_by(fn item -> {item.priority, item.created_at} end)
  end

  @doc """
  Claim a work item for an agent.

  Uses atomic ETS take-and-reinsert to prevent race conditions
  when multiple board workers poll simultaneously.
  """
  @spec claim(atom(), atom()) :: :ok | {:error, term()}
  def claim(id, agent_name) do
    # Atomic: take removes the entry so no other process can claim it
    case :ets.take(@table, id) do
      [] ->
        {:error, :not_found}

      [{^id, %{status: :ready} = item}] ->
        claimed = %{
          item
          | status: :claimed,
            claimed_by: agent_name,
            claimed_at: DateTime.utc_now()
        }

        :ets.insert(@table, {id, claimed})
        PubSub.broadcast({:work, :claimed, id, agent_name})
        :ok

      [{^id, %{status: status} = item}] ->
        # Not ready — put it back
        :ets.insert(@table, {id, item})
        {:error, {:invalid_transition, status, :claimed}}
    end
  end

  @doc """
  Mark a work item as in progress.
  """
  @spec start_work(atom()) :: :ok | {:error, term()}
  def start_work(id) do
    case get(id) do
      nil ->
        {:error, :not_found}

      %{status: :claimed} = item ->
        update(id, %{item | status: :in_progress, started_at: DateTime.utc_now()})
        PubSub.broadcast({:work, :started, id})
        :ok

      %{status: status} ->
        {:error, {:invalid_transition, status, :in_progress}}
    end
  end

  @doc """
  Mark a work item as done. Unblocks dependents.
  """
  @spec complete(atom(), String.t() | nil) :: :ok | {:error, term()}
  def complete(id, result \\ nil) do
    case get(id) do
      nil ->
        {:error, :not_found}

      %{status: status} = item when status in [:claimed, :in_progress] ->
        update(id, %{item | status: :done, result: result, completed_at: DateTime.utc_now()})
        Telemetry.event(:work_completed, %{}, %{id: id, type: item.type})
        PubSub.broadcast({:work, :completed, id})
        unblock_dependents(id)
        :ok

      %{status: status} ->
        {:error, {:invalid_transition, status, :done}}
    end
  end

  @doc """
  Mark a work item as failed.
  """
  @spec fail(atom(), String.t() | nil) :: :ok | {:error, term()}
  def fail(id, error \\ nil) do
    case get(id) do
      nil ->
        {:error, :not_found}

      %{status: status} = item when status in [:claimed, :in_progress] ->
        update(id, %{item | status: :failed, error: error, completed_at: DateTime.utc_now()})
        Telemetry.event(:work_failed, %{}, %{id: id, type: item.type, error: error})
        PubSub.broadcast({:work, :failed, id})
        block_dependents(id)
        :ok

      %{status: status} ->
        {:error, {:invalid_transition, status, :failed}}
    end
  end

  @doc """
  Cancel a work item.
  """
  @spec cancel(atom()) :: :ok | {:error, term()}
  def cancel(id) do
    case get(id) do
      nil ->
        {:error, :not_found}

      %{status: :done} ->
        {:error, :already_done}

      item ->
        update(id, %{item | status: :cancelled, completed_at: DateTime.utc_now()})
        PubSub.broadcast({:work, :cancelled, id})
        block_dependents(id)
        :ok
    end
  end

  @doc """
  Remove a work item from the board entirely.
  """
  @spec remove(atom()) :: :ok
  def remove(id) do
    :ets.delete(@table, id)
    :ok
  end

  @doc """
  Clear all work items.
  """
  @spec clear() :: :ok
  def clear do
    if :ets.info(@table) != :undefined do
      :ets.delete_all_objects(@table)
    end

    :ok
  end

  @doc """
  Summary counts by status.
  """
  @spec summary() :: map()
  def summary do
    list()
    |> Enum.group_by(& &1.status)
    |> Enum.map(fn {status, items} -> {status, length(items)} end)
    |> Map.new()
  end

  @doc false
  def valid_statuses, do: @valid_statuses

  @doc false
  def valid_types, do: @valid_types

  # ── Serialization ───────────────────────────────────────────

  @doc false
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = item) do
    %{
      "id" => Atom.to_string(item.id),
      "title" => item.title,
      "spec" => item.spec,
      "type" => Atom.to_string(item.type),
      "status" => Atom.to_string(item.status),
      "priority" => item.priority,
      "depends_on" => Enum.map(item.depends_on, &Atom.to_string/1),
      "claimed_by" => if(item.claimed_by, do: Atom.to_string(item.claimed_by)),
      "result" => item.result,
      "error" => item.error,
      "created_at" => if(item.created_at, do: DateTime.to_iso8601(item.created_at)),
      "claimed_at" => if(item.claimed_at, do: DateTime.to_iso8601(item.claimed_at)),
      "started_at" => if(item.started_at, do: DateTime.to_iso8601(item.started_at)),
      "completed_at" => if(item.completed_at, do: DateTime.to_iso8601(item.completed_at))
    }
  end

  @doc false
  @spec from_map(map()) :: t()
  def from_map(map) do
    %__MODULE__{
      id: String.to_atom(map["id"]),
      title: map["title"],
      spec: map["spec"],
      type: String.to_atom(map["type"]),
      status: String.to_atom(map["status"]),
      priority: map["priority"] || 3,
      depends_on: Enum.map(map["depends_on"] || [], &String.to_atom/1),
      claimed_by: if(map["claimed_by"], do: String.to_atom(map["claimed_by"])),
      result: map["result"],
      error: map["error"],
      created_at: parse_datetime(map["created_at"]),
      claimed_at: parse_datetime(map["claimed_at"]),
      started_at: parse_datetime(map["started_at"]),
      completed_at: parse_datetime(map["completed_at"])
    }
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  # ── Internal ────────────────────────────────────────────────

  defp update(id, item) do
    :ets.insert(@table, {id, item})
  end

  defp resolve_status(item) do
    if item.depends_on == [] or all_deps_done?(item.depends_on) do
      %{item | status: :ready}
    else
      %{item | status: :new}
    end
  end

  defp all_deps_done?(dep_ids) do
    Enum.all?(dep_ids, fn dep_id ->
      case get(dep_id) do
        %{status: :done} -> true
        _ -> false
      end
    end)
  end

  defp unblock_dependents(completed_id) do
    list()
    |> Enum.filter(fn item ->
      completed_id in item.depends_on and item.status in [:new, :blocked]
    end)
    |> Enum.each(fn item ->
      if all_deps_done?(item.depends_on) do
        update(item.id, %{item | status: :ready})
        PubSub.broadcast({:work, :ready, item.id})
      end
    end)
  end

  defp block_dependents(failed_id) do
    list()
    |> Enum.filter(fn item ->
      failed_id in item.depends_on and item.status in [:new, :ready]
    end)
    |> Enum.each(fn item ->
      update(item.id, %{item | status: :blocked})
      PubSub.broadcast({:work, :blocked, item.id})
    end)
  end

  defp apply_filters(items, []), do: items

  defp apply_filters(items, [{:status, status} | rest]) do
    items |> Enum.filter(&(&1.status == status)) |> apply_filters(rest)
  end

  defp apply_filters(items, [{:type, type} | rest]) do
    items |> Enum.filter(&(&1.type == type)) |> apply_filters(rest)
  end

  defp apply_filters(items, [{:claimed_by, agent} | rest]) do
    items |> Enum.filter(&(&1.claimed_by == agent)) |> apply_filters(rest)
  end

  defp apply_filters(items, [_ | rest]), do: apply_filters(items, rest)
end
