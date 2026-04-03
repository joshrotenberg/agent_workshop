defmodule AgentWorkshop.TableManager do
  @moduledoc false
  # Dedicated owner process for all Workshop ETS tables.
  #
  # ETS tables are destroyed when their owner process exits. Without this
  # GenServer, tables would be owned by whatever process happened to create
  # them (previously Workshop.configure/1 running in the caller's shell).
  # A dedicated owner that starts first in the supervision tree guarantees:
  #
  #   - Tables exist before any other child starts.
  #   - Tables survive individual child crashes (only a TableManager crash
  #     or full application shutdown destroys them).
  #   - Deterministic lifecycle: the supervisor controls creation and cleanup.

  use GenServer

  @tables [
    :agent_workshop_agents,
    :agent_workshop_store,
    :agent_workshop_work,
    :agent_workshop_budgets,
    :agent_workshop_profiles
  ]

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    for table <- @tables do
      if :ets.info(table) == :undefined do
        :ets.new(table, [:named_table, :public, :set])
      end
    end

    {:ok, %{}}
  end
end
