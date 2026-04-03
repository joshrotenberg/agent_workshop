defmodule AgentWorkshop.ProcessMonitor do
  @moduledoc false
  # Monitors SessionServer pids for agent processes.
  #
  # When an agent is created, Workshop registers its pid here.
  # If the SessionServer crashes, this GenServer receives :DOWN
  # and cleans up the ETS entry so the agent doesn't appear as
  # a zombie (pid in ETS but process dead).
  #
  # This is a centralized monitor — all agent pids are tracked
  # in one process to keep the architecture simple. Each monitor
  # ref maps to an agent name so we know what to clean up.

  use GenServer

  alias AgentWorkshop.{PubSub, Telemetry}

  @name __MODULE__
  @table :agent_workshop_agents

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: @name)
  end

  @doc """
  Start monitoring a pid for a named agent.
  Called by Workshop when an agent is created.
  """
  @spec monitor(atom(), pid()) :: :ok
  def monitor(agent_name, pid) when is_atom(agent_name) and is_pid(pid) do
    GenServer.cast(@name, {:monitor, agent_name, pid})
  end

  @doc """
  Stop monitoring an agent (called on dismiss).
  """
  @spec demonitor(atom()) :: :ok
  def demonitor(agent_name) when is_atom(agent_name) do
    GenServer.cast(@name, {:demonitor, agent_name})
  end

  # ── GenServer callbacks ─────────────────────────────────────

  @impl true
  def init(_) do
    # State: %{agent_name => monitor_ref}
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:monitor, agent_name, pid}, state) do
    # Demonitor old ref if exists (e.g., agent was reset)
    state = maybe_demonitor(state, agent_name)

    ref = Process.monitor(pid)
    {:noreply, Map.put(state, agent_name, ref)}
  end

  def handle_cast({:demonitor, agent_name}, state) do
    {:noreply, maybe_demonitor(state, agent_name)}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    # Find which agent this ref belongs to
    case Enum.find(state, fn {_name, r} -> r == ref end) do
      {agent_name, _ref} ->
        handle_agent_down(agent_name, reason)
        {:noreply, Map.delete(state, agent_name)}

      nil ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ── Internal ────────────────────────────────────────────────

  defp maybe_demonitor(state, agent_name) do
    case Map.get(state, agent_name) do
      nil ->
        state

      ref ->
        Process.demonitor(ref, [:flush])
        Map.delete(state, agent_name)
    end
  end

  defp handle_agent_down(agent_name, reason) do
    # Clean up the ETS entry — mark as crashed so status shows it
    case :ets.lookup(@table, agent_name) do
      [{^agent_name, entry}] ->
        updated = %{entry | status: :crashed, task: nil, task_text: nil}
        :ets.insert(@table, {agent_name, updated})

      [] ->
        :ok
    end

    Telemetry.event(:agent_crashed, %{}, %{agent: agent_name, reason: reason})
    PubSub.broadcast({:agent, :crashed, agent_name, reason})
  end
end
