defmodule AgentWorkshop.Persistence do
  @moduledoc """
  Persist work board, store, and events to disk.

  Subscribes to PubSub and writes state to JSON files on change. On startup,
  loads saved state back into ETS tables so work survives IEx restarts.

  ## Files

  - `work.json` -- full work board snapshot
  - `store.json` -- full store snapshot
  - `events.jsonl` -- append-only event log (one JSON object per line)

  ## Configuration

      configure(persistence: true)              # use .agent_workshop/ in cwd
      configure(persistence: "/path/to/dir")    # custom directory

  Persistence is disabled by default. When disabled, this GenServer is idle.
  """

  use GenServer

  alias AgentWorkshop.{PubSub, Store, Work}

  @name __MODULE__
  @default_dir ".agent_workshop"
  @debounce_ms 100

  defstruct dir: nil,
            enabled: false,
            pending: MapSet.new(),
            timer: nil,
            events_fd: nil

  # ── Client API ──────────────────────────────────────────────

  @doc false
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @name)
  end

  @doc """
  Enable persistence to the given directory.

  Pass `true` to use the default `.agent_workshop/` in the current directory,
  or a path string for a custom location.
  """
  @spec enable(boolean() | String.t()) :: :ok
  def enable(true), do: enable(@default_dir)
  def enable(false), do: disable()

  def enable(dir) when is_binary(dir) do
    GenServer.call(@name, {:enable, dir})
  end

  @doc """
  Disable persistence. Closes open file handles.
  """
  @spec disable() :: :ok
  def disable do
    GenServer.call(@name, :disable)
  end

  @doc """
  Check if persistence is currently enabled.
  """
  @spec enabled?() :: boolean()
  def enabled? do
    GenServer.call(@name, :enabled?)
  end

  @doc """
  Force an immediate flush of all pending writes.
  """
  @spec flush() :: :ok
  def flush do
    GenServer.call(@name, :flush)
  end

  # ── GenServer callbacks ─────────────────────────────────────

  @impl true
  def init(_opts) do
    try do
      PubSub.subscribe(:all)
    rescue
      _ -> :ok
    end

    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call({:enable, dir}, _from, state) do
    state = close_events_fd(state)
    File.mkdir_p!(dir)
    state = %{state | dir: dir, enabled: true}
    state = load_from_disk(state)
    state = open_events_fd(state)
    {:reply, :ok, state}
  end

  def handle_call(:disable, _from, state) do
    state = flush_pending(state)
    state = close_events_fd(state)
    {:reply, :ok, %{state | enabled: false, dir: nil}}
  end

  def handle_call(:enabled?, _from, state) do
    {:reply, state.enabled, state}
  end

  def handle_call(:flush, _from, state) do
    {:reply, :ok, flush_pending(state)}
  end

  @impl true
  def handle_info({:workshop_event, _topic, event}, state) do
    if state.enabled do
      state = append_event(state, event)
      state = schedule_write(state, event)
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  def handle_info(:do_flush, state) do
    {:noreply, flush_pending(%{state | timer: nil})}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    flush_pending(state)
    close_events_fd(state)
    :ok
  end

  # ── Write scheduling ────────────────────────────────────────

  defp schedule_write(state, event) do
    target = write_target(event)

    if target do
      state = %{state | pending: MapSet.put(state.pending, target)}

      if state.timer do
        state
      else
        timer = Process.send_after(self(), :do_flush, @debounce_ms)
        %{state | timer: timer}
      end
    else
      state
    end
  end

  defp write_target({:work, _, _}), do: :work
  defp write_target({:work, _, _, _}), do: :work
  defp write_target({:store, _, _}), do: :store
  defp write_target({:store, _}), do: :store
  defp write_target(_), do: nil

  defp flush_pending(state) do
    if state.enabled and state.dir do
      if :work in state.pending, do: write_work(state.dir)
      if :store in state.pending, do: write_store(state.dir)
    end

    if state.timer do
      Process.cancel_timer(state.timer)
    end

    %{state | pending: MapSet.new(), timer: nil}
  end

  # ── Snapshot writes ─────────────────────────────────────────

  defp write_work(dir) do
    items = Work.list() |> Enum.map(&Work.to_map/1)
    json = Jason.encode!(items, pretty: true)
    File.write!(Path.join(dir, "work.json"), json)
  end

  defp write_store(dir) do
    entries =
      Store.entries()
      |> Enum.map(fn {key, value} ->
        %{"key" => encode_term(key), "value" => encode_term(value)}
      end)

    json = Jason.encode!(entries, pretty: true)
    File.write!(Path.join(dir, "store.json"), json)
  end

  # ── Event append ────────────────────────────────────────────

  defp append_event(state, event) do
    if state.events_fd do
      entry = %{
        "event" => inspect(event),
        "timestamp" => DateTime.to_iso8601(DateTime.utc_now())
      }

      IO.write(state.events_fd, Jason.encode!(entry) <> "\n")
    end

    state
  end

  defp open_events_fd(state) do
    path = Path.join(state.dir, "events.jsonl")
    {:ok, fd} = File.open(path, [:append, :utf8])
    %{state | events_fd: fd}
  end

  defp close_events_fd(%{events_fd: nil} = state), do: state

  defp close_events_fd(%{events_fd: fd} = state) do
    File.close(fd)
    %{state | events_fd: nil}
  end

  # ── Load from disk ──────────────────────────────────────────

  defp load_from_disk(state) do
    load_work(state.dir)
    load_store(state.dir)
    state
  end

  defp load_work(dir) do
    path = Path.join(dir, "work.json")

    with {:ok, contents} <- read_json_file(path),
         {:ok, items} when is_list(items) <- Jason.decode(contents) do
      for map <- items do
        item = Work.from_map(map)
        :ets.insert(Work.table_name(), {item.id, item})
      end
    else
      _ -> :ok
    end
  end

  defp load_store(dir) do
    path = Path.join(dir, "store.json")

    with {:ok, contents} <- read_json_file(path),
         {:ok, entries} when is_list(entries) <- Jason.decode(contents) do
      for entry <- entries do
        key = decode_term(entry["key"])
        value = decode_term(entry["value"])
        :ets.insert(Store.table_name(), {key, value, System.monotonic_time()})
      end
    else
      _ -> :ok
    end
  end

  defp read_json_file(path) do
    if File.exists?(path), do: File.read(path), else: :skip
  end

  # ── Term encoding ───────────────────────────────────────────
  #
  # Store keys and values can be arbitrary Elixir terms. We encode
  # atoms with a prefix so they round-trip correctly through JSON.

  defp encode_term(term) when is_atom(term), do: "__atom__:#{term}"
  defp encode_term(term) when is_binary(term), do: term
  defp encode_term(term) when is_number(term), do: term
  defp encode_term(term) when is_boolean(term), do: term

  defp encode_term(term) when is_tuple(term) do
    %{"__tuple__" => term |> Tuple.to_list() |> Enum.map(&encode_term/1)}
  end

  defp encode_term(term) when is_list(term) do
    Enum.map(term, &encode_term/1)
  end

  defp encode_term(term) when is_map(term) do
    Map.new(term, fn {k, v} -> {encode_term(k), encode_term(v)} end)
  end

  defp encode_term(term), do: inspect(term)

  defp decode_term("__atom__:" <> name), do: String.to_atom(name)

  defp decode_term(%{"__tuple__" => elements}) when is_list(elements) do
    elements |> Enum.map(&decode_term/1) |> List.to_tuple()
  end

  defp decode_term(term) when is_binary(term), do: term
  defp decode_term(term) when is_number(term), do: term
  defp decode_term(term) when is_boolean(term), do: term

  defp decode_term(term) when is_list(term) do
    Enum.map(term, &decode_term/1)
  end

  defp decode_term(term) when is_map(term) do
    Map.new(term, fn {k, v} -> {decode_term(k), decode_term(v)} end)
  end

  defp decode_term(term), do: term
end
