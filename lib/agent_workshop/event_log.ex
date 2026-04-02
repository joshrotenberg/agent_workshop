defmodule AgentWorkshop.EventLog do
  @moduledoc """
  Event history and live streaming for Workshop operations.

  Subscribes to PubSub and stores events in a ring buffer. Optionally
  prints events live to the console as they happen.

  ## Usage from IEx

      watch()              # start printing live events
      unwatch()            # stop printing
      events()             # show last 20 events
      events(last: 50)     # show more
      clear_events()       # clear history
  """

  use GenServer

  alias AgentWorkshop.PubSub

  @name __MODULE__
  @default_max_events 500

  defstruct events: :queue.new(),
            count: 0,
            max_events: @default_max_events,
            watching: false,
            watch_pid: nil

  # ── Client API ──────────────────────────────────────────────

  @doc false
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @name)
  end

  @doc """
  Start printing live events to the console.
  """
  @spec watch() :: :ok
  def watch do
    GenServer.call(@name, {:watch, self()})
  end

  @doc """
  Stop printing live events.
  """
  @spec unwatch() :: :ok
  def unwatch do
    GenServer.call(@name, :unwatch)
  end

  @doc """
  Get recent events.
  """
  @spec recent(keyword()) :: [map()]
  def recent(opts \\ []) do
    limit = Keyword.get(opts, :last, 20)
    GenServer.call(@name, {:recent, limit})
  end

  @doc """
  Clear event history.
  """
  @spec clear() :: :ok
  def clear do
    GenServer.call(@name, :clear)
  end

  @doc """
  Is live watching enabled?
  """
  @spec watching?() :: boolean()
  def watching? do
    GenServer.call(@name, :watching?)
  end

  # ── GenServer callbacks ─────────────────────────────────────

  @impl true
  def init(opts) do
    max = Keyword.get(opts, :max_events, @default_max_events)

    try do
      PubSub.subscribe(:all)
    rescue
      _ -> :ok
    end

    {:ok, %__MODULE__{max_events: max}}
  end

  @impl true
  def handle_call({:watch, pid}, _from, state) do
    {:reply, :ok, %{state | watching: true, watch_pid: pid}}
  end

  def handle_call(:unwatch, _from, state) do
    {:reply, :ok, %{state | watching: false, watch_pid: nil}}
  end

  def handle_call({:recent, limit}, _from, state) do
    events =
      state.events
      |> :queue.to_list()
      |> Enum.take(-limit)

    {:reply, events, state}
  end

  def handle_call(:clear, _from, state) do
    {:reply, :ok, %{state | events: :queue.new(), count: 0}}
  end

  def handle_call(:watching?, _from, state) do
    {:reply, state.watching, state}
  end

  @impl true
  def handle_info({:workshop_event, _topic, event}, state) do
    entry = %{
      event: event,
      timestamp: DateTime.utc_now(),
      formatted: format_event(event)
    }

    # Print live if watching
    if state.watching and entry.formatted do
      IO.puts(IO.ANSI.light_black() <> entry.formatted <> IO.ANSI.reset())
    end

    # Store in ring buffer
    events = :queue.in(entry, state.events)
    count = state.count + 1

    {events, count} =
      if count > state.max_events do
        {:queue.drop(events), count - 1}
      else
        {events, count}
      end

    {:noreply, %{state | events: events, count: count}}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ── Event formatting ────────────────────────────────────────

  defp format_event({:agent, :created, name}) do
    "[agent] #{name} created"
  end

  defp format_event({:agent, :dismissed, name}) do
    "[agent] #{name} dismissed"
  end

  defp format_event({:agent, :reset, name}) do
    "[agent] #{name} reset"
  end

  defp format_event({:agent, :ask_complete, name, result}) do
    cost = format_cost(result[:cost_usd])
    text = truncate(result[:result] || "", 60)
    "[ask] #{name} complete #{cost} — #{text}"
  end

  defp format_event({:agent, :cast_complete, name, result}) do
    cost = format_cost(result[:cost_usd])
    text = truncate(result[:result] || "", 60)
    "[cast] #{name} complete #{cost} — #{text}"
  end

  defp format_event({:agent, :error, name, reason}) do
    "[error] #{name}: #{inspect(reason)}"
  end

  defp format_event({:store, :put, key}) do
    "[store] put #{inspect(key)}"
  end

  defp format_event({:store, :delete, key}) do
    "[store] delete #{inspect(key)}"
  end

  defp format_event({:store, :clear}) do
    "[store] cleared"
  end

  defp format_event({:work, action, id}) when is_atom(action) do
    "[work] #{id} #{action}"
  end

  defp format_event({:work, :claimed, id, agent}) do
    "[work] #{id} claimed by #{agent}"
  end

  defp format_event({:schedule, :tick, name}) do
    "[tick] #{name}"
  end

  defp format_event({:custom, topic, _data}) do
    "[event] #{inspect(topic)}"
  end

  defp format_event(_), do: nil

  defp format_cost(nil), do: ""
  defp format_cost(cost) when is_number(cost), do: "($#{Float.round(cost / 1, 2)})"
  defp format_cost(_), do: ""

  defp truncate(str, max) do
    if String.length(str) > max do
      String.slice(str, 0, max - 3) <> "..."
    else
      str
    end
  end
end
