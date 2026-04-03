defmodule AgentWorkshop.Scheduler do
  @moduledoc """
  Periodic task scheduler for Workshop agents.

  Runs agent prompts on a recurring interval. Each schedule is a
  GenServer that calls `cast/2` on each tick.

  ## Usage from IEx

      import AgentWorkshop.Workshop

      every(:monitor, "Check CI status", interval: :timer.minutes(5))
      schedules()          # list active schedules
      cancel(:monitor)     # stop a schedule

  ## Behavior

  - Each tick calls `cast(name, prompt)` (non-blocking)
  - If the agent is busy (cast queued), the tick is skipped
  - Schedules survive agent resets but not Workshop restarts
  - PubSub event `{:schedule, :tick, name}` on each run
  """

  use GenServer

  alias AgentWorkshop.{PubSub, Telemetry}

  @registry AgentWorkshop.Scheduler.Registry

  defstruct [:agent, :prompt, :interval, :timer_ref, run_count: 0, last_run_at: nil]

  # ── Client API ──────────────────────────────────────────────

  @doc false
  def start_link(opts) do
    agent = Keyword.fetch!(opts, :agent)
    GenServer.start_link(__MODULE__, opts, name: via(agent))
  end

  @doc false
  def stop(agent) do
    case Registry.lookup(@registry, agent) do
      [{pid, _}] ->
        try do
          GenServer.stop(pid, :normal, 3_000)
        catch
          :exit, _ ->
            if Process.alive?(pid), do: Process.exit(pid, :kill)
        end

      [] ->
        :ok
    end
  end

  @doc false
  def get_info(agent) do
    case Registry.lookup(@registry, agent) do
      [{pid, _}] -> GenServer.call(pid, :info)
      [] -> nil
    end
  end

  @doc false
  def list_all do
    @registry
    |> Registry.select([{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.filter(fn {_name, pid} -> Process.alive?(pid) end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.sort()
  end

  @doc false
  def start_registry do
    case Registry.start_link(keys: :unique, name: @registry) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end

  # ── GenServer callbacks ─────────────────────────────────────

  @impl true
  def init(opts) do
    agent = Keyword.fetch!(opts, :agent)
    prompt = Keyword.fetch!(opts, :prompt)
    interval = Keyword.fetch!(opts, :interval)

    state = %__MODULE__{
      agent: agent,
      prompt: prompt,
      interval: interval
    }

    timer_ref = Process.send_after(self(), :tick, interval)
    {:ok, %{state | timer_ref: timer_ref}}
  end

  @impl true
  # Task result messages from cast — ignore
  def handle_info({ref, _result}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:noreply, state}
  end

  def handle_info(:tick, state) do
    # Skip if agent is busy (don't pile up)
    try do
      info = AgentWorkshop.Workshop.info(state.agent)

      if info.status == :idle do
        AgentWorkshop.Workshop.cast(state.agent, state.prompt)
      end
    rescue
      _ -> :ok
    end

    Telemetry.event(:schedule_tick, %{}, %{agent: state.agent, run_count: state.run_count + 1})
    PubSub.broadcast({:schedule, :tick, state.agent})

    timer_ref = Process.send_after(self(), :tick, state.interval)

    {:noreply,
     %{
       state
       | timer_ref: timer_ref,
         run_count: state.run_count + 1,
         last_run_at: DateTime.utc_now()
     }}
  end

  @impl true
  def handle_call(:info, _from, state) do
    info = %{
      agent: state.agent,
      prompt: state.prompt,
      interval: state.interval,
      run_count: state.run_count,
      last_run_at: state.last_run_at
    }

    {:reply, info, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)
    :ok
  end

  defp via(agent) do
    {:via, Registry, {@registry, agent}}
  end
end
