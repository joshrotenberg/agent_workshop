defmodule AgentWorkshop.Budget do
  @moduledoc """
  Cost budget enforcement for Workshop agents.

  Configurable budgets at global and per-agent levels. When a budget
  is exceeded, `ask/2` and `cast/2` return `{:error, :budget_exceeded}`.

  ## Usage

      configure(max_cost_usd: 10.00)
      agent(:impl, "Coder", max_cost_usd: 2.00)

      budget()          # show global remaining
      budget(:impl)     # show per-agent remaining
      reset_budget()    # reset global tracking
  """

  @table :agent_workshop_budgets

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

  @doc """
  Set a global budget limit.
  """
  @spec set_global(float()) :: :ok
  def set_global(max_usd) when is_number(max_usd) do
    :ets.insert(@table, {:global_budget, max_usd})
    :ok
  end

  @doc """
  Set a per-agent budget limit.
  """
  @spec set_agent(atom(), float()) :: :ok
  def set_agent(name, max_usd) when is_atom(name) and is_number(max_usd) do
    :ets.insert(@table, {{:agent_budget, name}, max_usd})
    :ok
  end

  @doc """
  Check if spending `cost` for `agent` would exceed any budget.

  Returns `:ok` or `{:error, :budget_exceeded, reason}`.
  """
  @spec check(atom(), float(), float()) :: :ok | {:error, :budget_exceeded, String.t()}
  def check(agent_name, agent_cumulative_cost, additional_cost) do
    with :ok <- check_agent_budget(agent_name, agent_cumulative_cost, additional_cost) do
      check_global_budget(additional_cost)
    end
  end

  @doc """
  Get budget info for a specific agent or global.
  """
  @spec info(atom() | :global) :: map()
  def info(:global) do
    case get_global_limit() do
      nil ->
        %{limit: nil, spent: total_spent(), remaining: nil}

      limit ->
        spent = total_spent()
        %{limit: limit, spent: spent, remaining: max(limit - spent, 0.0)}
    end
  end

  def info(agent_name) do
    case get_agent_limit(agent_name) do
      nil -> %{limit: nil}
      limit -> %{limit: limit}
    end
  end

  @doc """
  Clear budget limits (does not reset cost tracking — costs are in ETS agent entries).
  """
  @spec clear() :: :ok
  def clear do
    if :ets.info(@table) != :undefined do
      :ets.delete_all_objects(@table)
    end

    :ok
  end

  # ── Internal ─────────────────────────────────────────────────

  defp check_agent_budget(agent_name, cumulative_cost, additional_cost) do
    case get_agent_limit(agent_name) do
      nil ->
        :ok

      limit when cumulative_cost + additional_cost > limit ->
        {:error, :budget_exceeded,
         "#{agent_name}: agent budget exceeded ($#{Float.round(cumulative_cost, 2)} of $#{Float.round(limit, 2)})"}

      _ ->
        :ok
    end
  end

  defp check_global_budget(additional_cost) do
    case get_global_limit() do
      nil ->
        :ok

      limit ->
        spent = total_spent()

        if spent + additional_cost > limit do
          {:error, :budget_exceeded,
           "global budget exceeded ($#{Float.round(spent, 2)} of $#{Float.round(limit, 2)})"}
        else
          :ok
        end
    end
  end

  defp get_global_limit do
    case :ets.lookup(@table, :global_budget) do
      [{:global_budget, limit}] -> limit
      [] -> nil
    end
  end

  defp get_agent_limit(name) do
    case :ets.lookup(@table, {:agent_budget, name}) do
      [{{:agent_budget, ^name}, limit}] -> limit
      [] -> nil
    end
  end

  defp total_spent do
    agents_table = :agent_workshop_agents

    if :ets.info(agents_table) != :undefined do
      :ets.tab2list(agents_table)
      |> Enum.map(fn {_name, entry} -> entry.cumulative_cost end)
      |> Enum.sum()
      |> Kernel./(1)
    else
      0.0
    end
  end
end
