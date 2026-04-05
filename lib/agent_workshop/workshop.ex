defmodule AgentWorkshop.Workshop do
  require Logger

  @moduledoc """
  Multi-agent IEx API for coordinating LLM CLI sessions.

  A naming and coordination layer over backend-specific session processes.
  Each agent is a supervised process addressed by name. All functions
  are designed to be called interactively after `import AgentWorkshop.Workshop`.

  ## Quick start

      # 1. Set backend and config (do this first -- affects all new agents)
      configure(backend: MyApp.ClaudeBackend,
        backend_config: %{working_dir: "~/projects/myapp"},
        context: "Elixir project. Run mix test before committing.")

      # 2. Create agents with roles
      agent(:impl, "You write clean, tested code.", max_turns: 15)
      agent(:reviewer, "You review code. Do not modify files.",
        model: "opus", allowed_tools: ["Read", "Bash"])

      # 3. Talk to them
      ask(:impl, "Implement caching for the user lookup")
      pipe(:impl, :reviewer, "Review for correctness")

      # 4. Check on things
      status()       # dashboard table
      total_cost()   # how much you've spent

  ## Sync vs async

  Two ways to send messages:

    * `ask/2` -- blocks until the agent responds, prints the result
    * `cast/2` -- returns immediately, agent works in the background

  Use `await/1` or `await_all/0` to collect async results. Use `status/0`
  to see who's busy.

  ## Coordination

    * `pipe/3` -- wait for one agent, forward its result to another
    * `fan/2` -- send the same message to multiple agents in parallel

  `ask/2` and `pipe/3` return the agent name on success, so they
  compose with Elixir's pipe operator:

      ask(:impl, "implement caching")
      |> pipe(:reviewer, "review for edge cases")
      |> pipe(:tests, "write tests for this")

  ## Inspecting agents

    * `status/0` -- dashboard of all agents
    * `info/1` -- detailed map for one agent (model, session_id, cost, ...)
    * `result/1` -- last response text (or pass `:full` for the full result map)
    * `history/1` -- print the full conversation
    * `cost/0` -- itemized costs; `cost/1` -- single agent; `total_cost/0` -- sum

  ## Lifecycle

    * `load/0` -- load `.workshop.exs` (auto-loaded on startup if present)
    * `load/1` -- load a specific setup file
    * `reset/1` -- clear an agent's conversation (keeps role and config)
    * `dismiss/1` -- remove an agent entirely
    * `reset_all/0` -- stop everything, clear config

  ## Architecture

  The OTP Application (`AgentWorkshop.Application`) owns the full lifecycle:
  ETS tables, registries, supervisors, and the EventLog. Workshop is the
  public IEx facade -- it reads and writes shared state but does not start
  or supervise any infrastructure. Call `configure/1` to set your backend;
  everything else is already running.

      Application supervisor (started automatically)
        |-- TableManager (owns ETS tables)
        |-- :persistent_term (global config -- no process needed)
        |-- Registry (PubSub, Scheduler, BoardWorker)
        |-- EventLog
        |-- DynamicSupervisor (agent sessions)
        `-- Task.Supervisor (async cast tasks)

      Workshop (this module -- IEx helpers, no supervision duties)
  """

  alias AgentWorkshop.{Budget, Profiles, PubSub, Scheduler, Store, Telemetry, Work}
  alias AgentWorkshop.Workshop.Display

  @table :agent_workshop_agents
  @sessions_sup AgentWorkshop.Workshop.SessionsSupervisor
  @tasks_sup AgentWorkshop.Workshop.TasksSupervisor

  @special_keys [
    :backend,
    :backend_config,
    :context,
    :workshop_tools,
    :skill,
    :max_cost_usd,
    :timeout,
    :persistence,
    :dashboard,
    :git_context
  ]
  @max_queue_size 5
  @valid_permission_modes [:default, :accept_edits, :bypass_permissions, :dont_ask, :plan, :auto]

  @doc """
  Stop the Workshop and clean up all state. Used for teardown in tests.

  Dismisses all agents, clears all ETS tables. The Application supervisor
  remains running — call `configure/1` to set up again.
  """
  @spec stop() :: :ok
  def stop do
    # Soft reset: dismiss agents and clear data, but leave the supervision
    # tree running. The Application supervisor, TableManager, registries,
    # and EventLog all survive -- only user-created state is removed.
    stop_all_processes()
    clear_all_tables()
    reset_global_state()
    :ok
  end

  defp stop_all_processes do
    safe_stop_each(agents(), &dismiss/1)
    safe_stop_each(Scheduler.list_all(), &Scheduler.stop/1)
    safe_stop_each(AgentWorkshop.BoardWorker.list_all(), &AgentWorkshop.BoardWorker.stop/1)
  end

  defp safe_stop_each(names, stop_fn) do
    for name <- names do
      try do
        stop_fn.(name)
      catch
        _, _ -> :ok
      end
    end
  end

  defp clear_all_tables do
    for table <- [
          @table,
          AgentWorkshop.Store.table_name(),
          AgentWorkshop.Work.table_name(),
          AgentWorkshop.Budget.table_name(),
          AgentWorkshop.Profiles.table_name()
        ] do
      if :ets.info(table) != :undefined, do: :ets.delete_all_objects(table)
    end
  end

  defp reset_global_state do
    for key <- [:backend, :backend_config, :query_opts, :context, :git_context] do
      :persistent_term.put({AgentWorkshop, key}, default_for(key))
    end
  end

  @doc false
  def default_state do
    %{backend: nil, backend_config: nil, query_opts: [permission_mode: :auto], context: nil}
  end

  @doc false
  def init_global_state do
    defaults = default_state()

    for {key, value} <- defaults do
      :persistent_term.put({AgentWorkshop, key}, value)
    end

    :ok
  end

  defp default_for(:query_opts), do: [permission_mode: :auto]
  defp default_for(_), do: nil

  # ── Configuration ─────────────────────────────────────────────

  @doc """
  Set global defaults inherited by all agents. Call this first.

  Changes affect new agents only; existing agents keep their config.

  ## Examples

      # Minimal
      configure(backend: MyApp.ClaudeBackend, backend_config: %{working_dir: "."})

      # Full setup
      configure(
        backend: MyApp.ClaudeBackend,
        backend_config: %{working_dir: "~/projects/myapp"},
        model: "sonnet",
        max_turns: 10,
        context: \"""
        Elixir project using Phoenix 1.7.
        Run mix test before considering any task complete.
        Use conventional commits.
        \"""
      )

  ## Permissions

  Workshop defaults to `permission_mode: :auto` so agents can work
  non-interactively (the CLI default of `:default` would hang waiting
  for approval that never comes). Override here to change for all agents:

      configure(permission_mode: :bypass_permissions)

  ## Options

  Backend options:

    * `:backend` -- module implementing `AgentWorkshop.Backend` (required on first call)
    * `:backend_config` -- backend-specific configuration (passed to `start_session/2`)

  Query options: `:model`, `:max_turns`, `:permission_mode`, `:max_budget_usd`, `:effort`

  Special:

    * `:context` -- global system prompt prepended to every agent's role.
      The effective system prompt for each agent is `context <> "\\n\\n" <> role`.
    * `:persistence` -- `true` (use `.agent_workshop/` in cwd), a path string,
      or `false` to disable. Saves work board and store to disk on change,
      reloads on next start.
  """
  @spec configure(keyword()) :: :ok
  def configure(opts \\ []) do
    {context, opts} = Keyword.pop(opts, :context)
    {backend, opts} = Keyword.pop(opts, :backend)
    {backend_config, opts} = Keyword.pop(opts, :backend_config)
    {mcp_opts, opts} = Keyword.pop(opts, :mcp)
    {max_cost_usd, opts} = Keyword.pop(opts, :max_cost_usd)
    {persistence, opts} = Keyword.pop(opts, :persistence)
    {dashboard_opts, opts} = Keyword.pop(opts, :dashboard)
    {git_context, opts} = Keyword.pop(opts, :git_context)
    query_opts = opts
    validate_opts!(query_opts)

    # Store config. Backend validation happens in agent/3, not here —
    # configure() can be called incrementally (e.g., set context first, backend later).
    if backend, do: :persistent_term.put({AgentWorkshop, :backend}, backend)
    if backend_config, do: :persistent_term.put({AgentWorkshop, :backend_config}, backend_config)
    if context, do: :persistent_term.put({AgentWorkshop, :context}, context)

    if query_opts != [] do
      current = :persistent_term.get({AgentWorkshop, :query_opts}, permission_mode: :auto)
      :persistent_term.put({AgentWorkshop, :query_opts}, Keyword.merge(current, query_opts))
    end

    if max_cost_usd, do: Budget.set_global(max_cost_usd)
    if mcp_opts, do: mcp_server(mcp_opts)

    if persistence != nil do
      AgentWorkshop.Persistence.enable(persistence)
    end

    if dashboard_opts do
      dashboard(dashboard_opts)
    end

    configure_git_context(git_context)

    :ok
  end

  # ── Agent Management ──────────────────────────────────────────

  @doc """
  Start a named agent.

  The role string is agent-specific context that composes with the global
  context from `configure/1`. If both are set, the effective system prompt
  is `context <> "\\n\\n" <> role`. Agent-specific options override globals.

  Calling `agent/3` with an existing name replaces that agent.

  ## Examples

      # Full agent with role and options
      agent(:impl, "You write clean, well-tested code.", max_turns: 15)

      # Read-only reviewer using opus
      agent(:reviewer, "You review code. Do not modify files.",
        model: "opus", allowed_tools: ["Read", "Bash"])

      # Minimal -- inherits everything from configure()
      agent(:scratch)

      # Options without a role
      agent(:fast, model: "haiku", max_turns: 3)

  ## Permissions

  Workshop defaults to `permission_mode: :auto` so agents can work
  non-interactively. Override per-agent or globally via `configure/1`:

      # Global: all agents use bypass
      configure(permission_mode: :bypass_permissions)

      # Per-agent: restrict the reviewer to default
      agent(:reviewer, "Review only.", permission_mode: :default)

  Valid modes: `:default`, `:accept_edits`, `:bypass_permissions`,
  `:dont_ask`, `:plan`, `:auto`.

  ## Options

  Core: `:model`, `:max_turns`, `:permission_mode`, `:max_budget_usd`, `:effort`

  Permissions: `:allowed_tools`, `:disallowed_tools`, `:dangerously_skip_permissions`

  Backend pass-through (Claude CLI): `:worktree`, `:mcp_config`, `:add_dir`,
  `:settings`, `:append_system_prompt`, `:no_session_persistence`

  Workshop-specific: `:workshop_tools`, `:skill`, `:max_cost_usd`, `:timeout`
  """
  @spec agent(atom(), String.t() | nil, keyword()) :: :ok
  def agent(name, role_or_opts \\ nil, opts \\ [])

  def agent(name, role, opts) when is_atom(name) and (is_binary(role) or is_nil(role)) do
    # Dismiss existing agent with same name
    if get_agent(name), do: dismiss(name)

    global = get_global_state()

    unless global.backend do
      raise ArgumentError,
            "no backend configured. Call configure(backend: MyModule) first."
    end

    # Extract special opts
    {workshop_tools, opts} = Keyword.pop(opts, :workshop_tools, false)
    {skill, opts} = Keyword.pop(opts, :skill)
    {agent_max_cost, opts} = Keyword.pop(opts, :max_cost_usd)
    {agent_timeout, opts} = Keyword.pop(opts, :timeout)

    # Compose system prompt: skill context + global context + role
    skill_context =
      AgentWorkshop.Skills.context_for(workshop_tools: workshop_tools, skill: skill)

    system_prompt = compose_system_prompt(skill_context, global.context, role)

    # Merge global query opts with agent-specific opts (agent wins)
    agent_query_opts = split_opts(opts)
    validate_opts!(agent_query_opts)
    query_opts = Keyword.merge(global.query_opts, agent_query_opts)

    # If workshop_tools: true, inject MCP config so agent can orchestrate
    query_opts =
      if workshop_tools do
        mcp_path = write_workshop_mcp_config()

        Keyword.update(query_opts, :mcp_config, [mcp_path], fn paths ->
          paths ++ [mcp_path]
        end)
      else
        query_opts
      end

    query_opts =
      if system_prompt do
        Keyword.put(query_opts, :system_prompt, system_prompt)
      else
        query_opts
      end

    backend = global.backend
    backend_config = global.backend_config

    {:ok, pid} =
      DynamicSupervisor.start_child(@sessions_sup, %{
        id: :"workshop_agent_#{name}",
        start: {__MODULE__, :start_backend_session, [backend, backend_config, query_opts]},
        restart: :temporary
      })

    entry = %{
      pid: pid,
      backend: backend,
      backend_config: backend_config,
      role: role,
      agent_opts: opts,
      query_opts: query_opts,
      timeout: agent_timeout,
      status: :idle,
      task: nil,
      task_text: nil,
      queue: [],
      cumulative_cost: 0.0,
      turn_count: 0,
      last_result: nil
    }

    :ets.insert(@table, {name, entry})
    if agent_max_cost, do: Budget.set_agent(name, agent_max_cost)
    # Monitor the session process — auto-cleanup if it crashes
    AgentWorkshop.ProcessMonitor.monitor(name, pid)
    global = get_global_state()
    Telemetry.event(:agent_created, %{}, %{agent: name, role: role, backend: global.backend})
    PubSub.broadcast({:agent, :created, name})
    :ok
  end

  def agent(name, opts, []) when is_atom(name) and is_list(opts) do
    agent(name, nil, opts)
  end

  @doc false
  def start_backend_session(backend, backend_config, query_opts) do
    backend.start_session(backend_config, query_opts)
  end

  @doc """
  List all agent names, sorted alphabetically.

  ## Example

      agents()    # => [:impl, :reviewer, :tests]
  """
  @spec agents() :: [atom()]
  def agents do
    :ets.tab2list(@table) |> Enum.map(&elem(&1, 0)) |> Enum.sort()
  end

  @doc """
  Remove an agent entirely. Stops its process and discards all state.

  No-op if the agent doesn't exist. Use `reset/1` instead if you want
  to keep the agent but clear its conversation.
  """
  @spec dismiss(atom()) :: :ok
  def dismiss(name) do
    case get_agent(name) do
      nil ->
        :ok

      entry ->
        AgentWorkshop.ProcessMonitor.demonitor(name)
        force_stop_agent(entry)
        :ets.delete(@table, name)
        Telemetry.event(:agent_dismissed, %{}, %{agent: name})
        PubSub.broadcast({:agent, :dismissed, name})
        :ok
    end
  end

  @doc """
  Reset an agent's conversation. Keeps the role, model, and all config.

  The agent gets a fresh session -- like calling `agent/3` again with
  the same arguments. Cost tracking is also reset to zero.

  ## Example

      ask(:impl, "Write some code")
      # ... not happy with the direction ...
      reset(:impl)
      ask(:impl, "Try a different approach")   # fresh conversation
  """
  @spec reset(atom()) :: :ok
  def reset(name) do
    entry = get_agent!(name)

    force_stop_agent(entry)

    global = get_global_state()

    # Reconstruct skill context for reset
    workshop_tools = Keyword.get(entry.agent_opts, :workshop_tools, false)
    skill = Keyword.get(entry.agent_opts, :skill)

    skill_context =
      AgentWorkshop.Skills.context_for(workshop_tools: workshop_tools, skill: skill)

    system_prompt = compose_system_prompt(skill_context, global.context, entry.role)

    agent_query_opts = split_opts(entry.agent_opts)
    query_opts = Keyword.merge(global.query_opts, agent_query_opts)

    query_opts =
      if system_prompt do
        Keyword.put(query_opts, :system_prompt, system_prompt)
      else
        query_opts
      end

    backend = entry.backend
    backend_config = entry.backend_config

    # Start fresh session
    {:ok, pid} =
      DynamicSupervisor.start_child(@sessions_sup, %{
        id: :"workshop_agent_#{name}",
        start: {__MODULE__, :start_backend_session, [backend, backend_config, query_opts]},
        restart: :temporary
      })

    updated = %{
      entry
      | pid: pid,
        status: :idle,
        task: nil,
        task_text: nil,
        queue: [],
        cumulative_cost: 0.0,
        turn_count: 0,
        last_result: nil
    }

    :ets.insert(@table, {name, updated})
    PubSub.broadcast({:agent, :reset, name})
    :ok
  end

  @doc """
  Stop all agents and clear global config. The nuclear option.

  After this, you'll need to call `configure/1` and `agent/3` again.
  """
  @spec reset_all() :: :ok
  def reset_all do
    agents() |> Enum.each(&dismiss/1)
    reset_global_state()
    :ok
  end

  @doc """
  Load a Workshop setup file (`.exs`).

  The file is evaluated with `import AgentWorkshop.Workshop` in scope,
  so it can call `configure/1`, `agent/3`, etc. directly.

  With no argument, looks for `.workshop.exs` in the current directory.

  ## Example file (.workshop.exs)

      configure(backend: MyApp.ClaudeBackend,
        backend_config: %{working_dir: "."},
        model: "sonnet",
        context: "Elixir project. Run mix test before committing.")

      agent(:impl, "You write clean code.", max_turns: 15)
      agent(:reviewer, "Review only.", model: "opus",
        allowed_tools: ["Read", "Bash"])

  ## Examples

      load()                        # loads .workshop.exs
      load("setups/review.exs")     # loads a specific file
  """
  @spec load(String.t()) :: :ok | {:error, :not_found}
  def load(path \\ ".workshop.exs") do
    path = Path.expand(path)

    if File.exists?(path) do
      code = "import AgentWorkshop.Workshop\n" <> File.read!(path)
      Code.eval_string(code, [], file: path)
      print_info("Loaded #{path}")
      :ok
    else
      print_error("File not found: #{path}")
      {:error, :not_found}
    end
  end

  @doc """
  Start the Workshop MCP server.

  Exposes all Workshop functions as MCP tools over HTTP.
  Requires `anubis_mcp`, `bandit`, and `plug` deps.

  Can also be triggered via `configure(mcp: [port: 4222])`.

  ## Examples

      mcp_server()                # start on default port 4222
      mcp_server(port: 8080)      # custom port
  """
  @spec mcp_server(keyword() | boolean()) :: :ok | {:error, term()}
  def mcp_server(opts \\ [])

  def mcp_server(true), do: mcp_server([])

  def mcp_server(opts) when is_list(opts) do
    mcp_mod = AgentWorkshop.MCP

    if Code.ensure_loaded?(mcp_mod) do
      try do
        case mcp_mod.start(opts) do
          {:ok, _pid} ->
            port = Keyword.get(opts, :port, 4222)
            print_info("MCP server started on port #{port}")
            :ok

          {:error, {:already_started, _pid}} ->
            :ok

          {:error, reason} ->
            print_error("MCP server failed to start: #{inspect(reason)}")
            {:error, reason}
        end
      catch
        :exit, reason ->
          print_error("MCP server failed to start: #{inspect(reason)}")
          {:error, reason}
      end
    else
      print_error("MCP server requires anubis_mcp, bandit, and plug deps.")
      {:error, :deps_missing}
    end
  end

  # ── Dashboard ─────────────────────────────────────────────────

  @doc """
  Start the LiveView dashboard.

  ## Options

    * `:port` - HTTP port (default 4223)

  ## Examples

      dashboard()              # start on port 4223
      dashboard(port: 8080)    # custom port
  """
  @spec dashboard(keyword()) :: :ok | {:error, term()}
  def dashboard(opts \\ [])

  def dashboard(true), do: dashboard([])

  def dashboard(opts) when is_list(opts) do
    dashboard_mod = AgentWorkshop.Dashboard

    if Code.ensure_loaded?(dashboard_mod) do
      case dashboard_mod.start(opts) do
        {:ok, _pid} ->
          :ok

        {:error, reason} ->
          print_error("Dashboard failed to start: #{inspect(reason)}")
          {:error, reason}
      end
    else
      print_error("Dashboard requires phoenix, phoenix_live_view, and phoenix_html deps.")
      {:error, :deps_missing}
    end
  end

  # ── Git Context ───────────────────────────────────────────────

  @doc """
  Get a structured summary of the current git state.

  Returns branch, status, recent commits, and file changes.
  Requires the optional `git` dependency.

  ## Example

      git_summary()
      # => %{branch: "main", dirty: true, staged: 1, ...}
  """
  @spec git_summary(keyword()) :: {:ok, map()} | {:error, term()}
  def git_summary(opts \\ []) do
    git_mod = AgentWorkshop.GitContext

    if Code.ensure_loaded?(git_mod) do
      git_mod.summary(opts)
    else
      {:error, :git_dep_missing}
    end
  end

  @doc """
  Get uncommitted changes as a diff string.
  """
  @spec git_diff(keyword()) :: {:ok, String.t()} | {:error, term()}
  def git_diff(opts \\ []) do
    git_mod = AgentWorkshop.GitContext

    if Code.ensure_loaded?(git_mod) do
      git_mod.changes(opts)
    else
      {:error, :git_dep_missing}
    end
  end

  defp configure_git_context(nil), do: :ok

  defp configure_git_context(git_context) do
    :persistent_term.put({AgentWorkshop, :git_context}, git_context)
    if git_context, do: inject_git_context()
  end

  defp inject_git_context do
    git_mod = AgentWorkshop.GitContext

    if Code.ensure_loaded?(git_mod) do
      apply_git_context(git_mod)
    else
      print_error("Git context requires the git dep. Add {:git, \"~> 0.2\"} to mix.exs.")
    end
  end

  defp apply_git_context(git_mod) do
    case git_mod.build() do
      nil ->
        :ok

      git_ctx ->
        current = :persistent_term.get({AgentWorkshop, :context}, nil)
        base = strip_git_context(current)
        new_context = if base, do: base <> "\n\n" <> git_ctx, else: git_ctx
        :persistent_term.put({AgentWorkshop, :context}, new_context)
        line_count = git_ctx |> String.split("\n") |> length()
        print_info("Git context injected (#{line_count} lines)")
    end
  end

  defp strip_git_context(nil), do: nil

  defp strip_git_context(context) do
    case String.split(context, "\n## Git Context\n", parts: 2) do
      [base, _] -> String.trim_trailing(base)
      [_] -> context
    end
  end

  # ── Shared State ──────────────────────────────────────────────

  @doc """
  Put a value in the shared store.

  Keys can be any term. Use tuples for namespacing.

  ## Examples

      put(:spec, "LRU cache with TTL support")
      put({:impl, :notes}, "Chose GenServer over Agent")
  """
  defdelegate put(key, value), to: Store

  @doc """
  Get a value from the shared store.

  Returns `nil` if the key does not exist. See `get/2` to supply a default.

  ## Examples

      iex> put(:spec, "LRU cache with TTL")
      iex> get(:spec)
      "LRU cache with TTL"

      iex> get(:nonexistent)
      nil
  """
  defdelegate get(key), to: Store

  @doc """
  Get a value from the shared store, returning `default` if the key is missing.

  ## Examples

      iex> get(:missing, "fallback")
      "fallback"

      iex> put(:count, 5)
      iex> get(:count, 0)
      5
  """
  defdelegate get(key, default), to: Store

  @doc """
  List all keys currently in the shared store.

  Returns an empty list when the store has no entries.

  ## Examples

      iex> put(:spec, "cache design")
      iex> put(:notes, "use GenServer")
      iex> store_keys()
      [:notes, :spec]

      iex> store_keys()
      []
  """
  def store_keys, do: Store.keys()

  @doc """
  Delete a key from the shared store.

  No-op if the key does not exist.

  ## Examples

      iex> put(:scratch, "temp value")
      iex> store_delete(:scratch)
      :ok
      iex> get(:scratch)
      nil
  """
  defdelegate store_delete(key), to: Store, as: :delete

  @doc """
  Print all entries in the shared store to the console.

  Each entry is displayed as `key: value`. Prints "Store is empty." when
  the store has no entries.

  ## Example

      iex> put(:spec, "LRU cache")
      iex> put(:status, :draft)
      iex> store()
        :spec: "LRU cache"
        :status: :draft
      :ok
  """
  def store do
    entries = Store.entries()

    if entries == [] do
      print_info("Store is empty.")
    else
      Enum.each(entries, fn {key, value} ->
        val_str = inspect(value, limit: 80, printable_limit: 200)
        IO.puts("  #{inspect(key)}: #{val_str}")
      end)
    end

    entries
  end

  # ── Event Log ─────────────────────────────────────────────────

  @doc """
  Start printing live events to the console.

  Shows agent creation/dismissal, ask/cast completions with cost,
  work board changes, errors, and more.

  ## Example

      watch()
      cast(:impl, "do something")
      # [agent] impl created
      # [cast] impl complete ($0.04) — Here is the implementation...
  """
  @spec watch() :: :ok
  def watch do
    AgentWorkshop.EventLog.watch()
    print_info("Watching events. Use unwatch() to stop.")
    :ok
  end

  @doc """
  Stop printing live events.
  """
  @spec unwatch() :: :ok
  def unwatch do
    AgentWorkshop.EventLog.unwatch()
    print_info("Stopped watching.")
    :ok
  end

  @doc """
  Show recent events.

  ## Options

    * `:last` - number of events to show (default 20)

  ## Examples

      events()            # last 20
      events(last: 50)    # last 50
  """
  @spec events(keyword()) :: [map()]
  def events(opts \\ []) do
    entries = AgentWorkshop.EventLog.recent(opts)

    if entries == [] do
      print_info("No events recorded.")
    else
      entries
      |> Enum.filter(& &1.formatted)
      |> Enum.each(&print_event/1)
    end

    entries
  end

  @doc """
  Clear all recorded events from the event log.

  After calling this, `events/0` will show no entries until new events occur.

  ## Example

      iex> clear_events()
      :ok
  """
  @spec clear_events() :: :ok
  def clear_events do
    AgentWorkshop.EventLog.clear()
    :ok
  end

  # ── Scheduling ────────────────────────────────────────────────

  @doc """
  Run an agent prompt on a recurring interval.

  ## Examples

      every(:monitor, "Check CI status", interval: :timer.minutes(5))
      every(:sweeper, "Clean up stale branches", interval: :timer.hours(1))
  """
  @spec every(atom(), String.t(), keyword()) :: :ok
  def every(name, prompt, opts) do
    get_agent!(name)
    interval = Keyword.fetch!(opts, :interval)

    # Stop existing schedule for this agent (wait for Registry cleanup)
    Scheduler.stop(name)
    Process.sleep(10)

    {:ok, _pid} =
      DynamicSupervisor.start_child(@sessions_sup, {
        Scheduler,
        agent: name, prompt: prompt, interval: interval
      })

    print_info("#{inspect(name)}: scheduled every #{format_interval(interval)}")
    :ok
  end

  @doc """
  List active schedules.
  """
  @spec schedules() :: [map()]
  def schedules do
    agents = Scheduler.list_all()

    infos =
      agents
      |> Enum.map(&Scheduler.get_info/1)
      |> Enum.reject(&is_nil/1)

    if infos == [] do
      print_info("No active schedules.")
    else
      Enum.each(infos, &print_schedule_info/1)
    end

    infos
  end

  @doc """
  Cancel a recurring schedule for an agent.

  Stops the agent from executing its scheduled prompt. The agent itself
  remains available for manual interaction. No-op if the agent has no
  active schedule.

  ## Example

      iex> every(:monitor, "Check CI status", interval: :timer.minutes(5))
      iex> cancel(:monitor)
      :ok
  """
  @spec cancel(atom()) :: :ok
  def cancel(name) do
    Scheduler.stop(name)
    :ok
  end

  # ── Budget ───────────────────────────────────────────────────

  @doc """
  Show budget info. With no argument, shows global. With an agent name, shows per-agent.

  ## Examples

      budget()          # global budget info
      budget(:impl)     # per-agent budget
  """
  @spec budget(atom() | :global) :: map()
  def budget(target \\ :global)

  def budget(:global) do
    info = Budget.info(:global)

    if info.limit do
      print_info(
        "Global: $#{Float.round(info.spent, 2)} / $#{Float.round(info.limit, 2)} " <>
          "($#{Float.round(info.remaining, 2)} remaining)"
      )
    else
      print_info("Global: no budget set (spent $#{Float.round(info.spent, 2)})")
    end

    info
  end

  def budget(name) when is_atom(name) do
    entry = get_agent!(name)
    agent_info = Budget.info(name)

    if agent_info.limit do
      remaining = max(agent_info.limit - entry.cumulative_cost, 0.0)

      print_info(
        "#{inspect(name)}: $#{Float.round(entry.cumulative_cost, 2)} / $#{Float.round(agent_info.limit, 2)} " <>
          "($#{Float.round(remaining, 2)} remaining)"
      )
    else
      print_info(
        "#{inspect(name)}: no budget set (spent $#{Float.round(entry.cumulative_cost, 2)})"
      )
    end

    agent_info
  end

  @doc """
  Reset all budget tracking.

  Clears both global and per-agent budget limits and spent totals.
  After calling this, agents can spend without budget restrictions
  until new limits are set via `configure(max_cost_usd: ...)` or
  per-agent `agent(:name, "role", max_cost_usd: ...)`.

  ## Example

      iex> reset_budget()
      :ok
  """
  @spec reset_budget() :: :ok
  def reset_budget do
    Budget.clear()
    print_info("Budgets cleared.")
    :ok
  end

  # ── Profiles ──────────────────────────────────────────────────

  @doc """
  Define a reusable agent profile (template).

  ## Examples

      profile(:coder, "You write clean code.", max_turns: 15)
      profile(:reviewer, "Review only.", model: "opus", allowed_tools: ["Read", "Bash"])
  """
  @spec profile(atom(), String.t() | nil, keyword()) :: :ok
  def profile(name, role \\ nil, opts \\ []) do
    Profiles.define(name, role, opts)
  end

  @doc """
  Create an agent from a profile.

  ## Examples

      profile(:coder, "You write code.", max_turns: 15)
      from_profile(:coder, :coder_bug_42)
      from_profile(:coder, :coder_feature_7, max_turns: 25)  # override opts
  """
  @spec from_profile(atom(), atom(), keyword()) :: :ok
  def from_profile(profile_name, agent_name, overrides \\ []) do
    case Profiles.get(profile_name) do
      nil ->
        raise ArgumentError,
              "unknown profile #{inspect(profile_name)}. Define it with profile/3."

      %{role: role, opts: base_opts} ->
        merged_opts = Keyword.merge(base_opts, overrides)
        agent(agent_name, role, merged_opts)
    end
  end

  @doc """
  List available profiles.
  """
  @spec profiles() :: [{atom(), map()}]
  def profiles do
    names = Profiles.list()

    entries =
      names
      |> Enum.map(&{&1, Profiles.get(&1)})
      |> Enum.reject(fn {_, v} -> is_nil(v) end)

    if entries == [] do
      print_info("No profiles defined.")
    else
      Enum.each(entries, &print_profile/1)
    end

    entries
  end

  # ── Work Board ────────────────────────────────────────────────

  @doc """
  Add a work item to the board.

  ## Options

    * `:type` - work type (`:code`, `:review`, `:test`, `:docs`, `:deploy`, `:triage`, `:custom`)
    * `:spec` - detailed specification
    * `:priority` - 1 (highest) to 5 (lowest), default 3
    * `:depends_on` - list of work item IDs that must complete first

  ## Examples

      work(:cache, "Implement LRU cache",
        type: :code, priority: 1,
        spec: "LRU cache with configurable max size and TTL per entry")

      work(:cache_review, "Review cache implementation",
        type: :review, depends_on: [:cache])
  """
  @spec work(atom(), String.t(), keyword()) :: :ok
  def work(id, title, opts \\ []) do
    Work.add(id, title, opts)
  end

  @doc """
  Show the work board. Optionally filter by status or type.

  ## Examples

      board()                    # full board
      board(status: :ready)      # items ready to pick up
      board(type: :code)         # only code tasks
  """
  @spec board(keyword()) :: [Work.t()]
  def board(filters \\ []) do
    items = Work.list(filters)

    if items == [] do
      print_info("Board is empty.")
    else
      Enum.each(items, &print_work_item/1)

      summary = Work.summary()
      parts = Enum.map_join(summary, ", ", fn {status, count} -> "#{status}: #{count}" end)
      print_info(parts)
    end

    items
  end

  @doc """
  Claim a work item for an agent.

  ## Example

      claim(:cache, :impl)
  """
  @spec claim_work(atom(), atom()) :: :ok | {:error, term()}
  def claim_work(id, agent_name) do
    get_agent!(agent_name)

    case Work.claim(id, agent_name) do
      :ok ->
        print_info("#{inspect(agent_name)} claimed #{inspect(id)}")
        :ok

      {:error, reason} ->
        print_error("Cannot claim #{inspect(id)}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Mark a work item as in progress.

  Transitions a work item from `:ready` (or `:claimed`) to `:in_progress`.
  Typically called after an agent has claimed the item with `claim_work/2`.

  ## Example

      iex> work(:cache, "Implement LRU cache", type: :code)
      iex> claim_work(:cache, :impl)
      iex> start_work(:cache)
      :ok
  """
  @spec start_work(atom()) :: :ok | {:error, term()}
  def start_work(id) do
    case Work.start_work(id) do
      :ok ->
        :ok

      {:error, reason} ->
        print_error("Cannot start #{inspect(id)}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Mark a work item as done. Unblocks any dependents.

  ## Examples

      complete_work(:cache)
      complete_work(:cache, "Implemented with GenServer-backed LRU")
  """
  @spec complete_work(atom(), String.t() | nil) :: :ok | {:error, term()}
  def complete_work(id, result \\ nil) do
    case Work.complete(id, result) do
      :ok ->
        print_info("#{inspect(id)} done.")
        :ok

      {:error, reason} ->
        print_error("Cannot complete #{inspect(id)}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Mark a work item as failed with an optional error message.

  Transitions the item to `:failed` status. Unlike `cancel_work/1`, this
  indicates the work was attempted but did not succeed.

  ## Examples

      iex> fail_work(:cache, "Tests failed: 3 assertions")
      :ok

      iex> fail_work(:cache)
      :ok
  """
  @spec fail_work(atom(), String.t() | nil) :: :ok | {:error, term()}
  def fail_work(id, error \\ nil) do
    case Work.fail(id, error) do
      :ok ->
        print_error("#{inspect(id)} failed: #{error || "no reason"}")
        :ok

      {:error, reason} ->
        print_error("Cannot fail #{inspect(id)}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Cancel a work item, removing it from active consideration.

  Transitions the item to `:cancelled` status. Unlike `fail_work/2`, this
  indicates the work was intentionally abandoned rather than attempted
  and failed.

  ## Example

      iex> work(:cache, "Implement LRU cache", type: :code)
      iex> cancel_work(:cache)
      :ok
  """
  @spec cancel_work(atom()) :: :ok | {:error, term()}
  def cancel_work(id) do
    case Work.cancel(id) do
      :ok ->
        print_info("#{inspect(id)} cancelled.")
        :ok

      {:error, reason} ->
        print_error("Cannot cancel #{inspect(id)}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Get details of a specific work item.

  Returns the full work item struct including status, type, priority,
  dependencies, claimed agent, and result. Returns `nil` if the item
  does not exist.

  ## Examples

      iex> work(:cache, "Implement LRU cache", type: :code, priority: 1)
      iex> item = work_item(:cache)
      iex> item.title
      "Implement LRU cache"
      iex> item.status
      :ready

      iex> work_item(:nonexistent)
      nil
  """
  @spec work_item(atom()) :: Work.t() | nil
  def work_item(id) do
    Work.get(id)
  end

  @doc """
  Create a work item from an agent's last result.

  Uses `result(agent_name)` as the spec for the new work item.
  Useful for turning an agent's analysis, plan, or review into
  actionable board items.

  ## Examples

      ask(:arch, "Review the architecture of this project")
      work_from_result(:arch, :refactor, type: :code, title: "Address architecture findings")

      ask(:planner, "Break this feature into tasks")
      work_from_result(:planner, :feature_impl, type: :code)
  """
  @spec work_from_result(atom(), atom(), keyword()) :: :ok
  def work_from_result(agent_name, work_id, opts \\ []) do
    spec = result(agent_name) || raise ArgumentError, "#{inspect(agent_name)} has no result"
    title = Keyword.get(opts, :title, "From #{agent_name} result")
    opts = Keyword.put(Keyword.delete(opts, :title), :spec, spec)
    Work.add(work_id, title, opts)
  end

  # ── Board Workers ────────────────────────────────────────────

  @doc """
  Create a board worker — an agent that polls the board for work.

  Combines a profile, an agent, and a poll loop. The worker claims
  ready items matching its work type, executes them, and marks them
  complete.

  ## Options

    * `:profile` - (required) profile name to create the agent from
    * `:interval` - poll interval in ms (default: 60_000 / 1 min)
    * `:worktree` - when `true`, passes `worktree: true` to the agent's query opts,
      enabling the Claude CLI `--worktree` flag for isolated parallel execution

  ## Examples

      board_worker(:coder_1, :code, profile: :coder, interval: :timer.minutes(1))
      board_worker(:reviewer_1, :review, profile: :reviewer, interval: :timer.minutes(2))

      # Post work — workers pick it up automatically
      work(:feature, "Implement feature X", type: :code, spec: "...")
  """
  @spec board_worker(atom(), atom(), keyword()) :: :ok
  def board_worker(name, work_type, opts \\ []) do
    profile_name = Keyword.fetch!(opts, :profile)
    interval = Keyword.get(opts, :interval, 60_000)
    worktree = Keyword.get(opts, :worktree, false)

    # Create the agent from profile, threading worktree into query_opts
    from_profile(profile_name, name, Keyword.drop(opts, [:profile, :interval]))

    # Start the board worker loop
    {:ok, _pid} =
      DynamicSupervisor.start_child(@sessions_sup, {
        AgentWorkshop.BoardWorker,
        agent_name: name, work_type: work_type, interval: interval, worktree: worktree
      })

    print_info(
      "#{inspect(name)}: board worker for #{inspect(work_type)} (every #{format_interval(interval)})"
    )

    :ok
  end

  @doc """
  Print a summary of all active board workers.

  Board workers are agents that automatically poll the work board for
  items matching their work type, claim them, execute them, and mark
  them complete. Shows each worker's type, completed count, and current
  item (if any). Prints "No board workers." when none are running.

  ## Example

      iex> workers()
        :coder_1: code, 3 completed
        :reviewer_1: review, 1 completed (working on :cache_review)
      :ok
  """
  @spec workers() :: [map()]
  def workers do
    names = AgentWorkshop.BoardWorker.list_all()

    infos =
      names
      |> Enum.map(&AgentWorkshop.BoardWorker.get_info/1)
      |> Enum.reject(&is_nil/1)

    if infos == [] do
      print_info("No board workers.")
    else
      Enum.each(infos, &print_worker_info/1)
    end

    infos
  end

  # ── Interaction ───────────────────────────────────────────────

  @doc """
  Send a message and wait for the response. Prints the result when done.

  This is the primary way to talk to an agent. Each call continues the
  agent's conversation (the session ID is threaded automatically).

  If the agent has a pending async task from `cast/2`, waits for it first.

  Returns the agent name on success, enabling `|>` chaining with `pipe/3`:

      ask(:impl, "implement caching")
      |> pipe(:reviewer, "review for edge cases")

  ## Examples

      ask(:impl, "What modules are in this project?")
      ask(:impl, "Now add tests for the retry module")   # continues conversation
      ask(:impl, "What files did you change?")            # still the same session
  """
  @spec ask(atom(), String.t()) :: atom() | {:error, term()}
  def ask(name, prompt) do
    consume_pending_task(name)
    do_send_sync(name, prompt)
  end

  @doc """
  Send a message asynchronously. Returns `:ok` immediately.

  The agent works in the background while you do other things.
  Use `status/0` to check progress, `await/1` to collect the result.

  If the agent is already working, the message is queued (up to
  #{@max_queue_size} deep). Queued messages are processed in order
  after the current task finishes.

  ## Examples

      cast(:impl, "Implement the caching layer from issue #12")
      cast(:tests, "Add property-based tests for lib/myapp/encoder.ex")

      # Queue a follow-up while :impl is still working
      cast(:impl, "Also add the cache invalidation")

      # Go think about something else...
      status()        # see who's done (shows queue depth)
      await(:impl)    # block until current + queued work finishes
      await_all()     # wait for everyone
  """
  @spec cast(atom(), String.t()) :: :ok | {:error, :queue_full}
  def cast(name, prompt) do
    entry = get_agent!(name)

    if entry.status == :working do
      if length(entry.queue) >= @max_queue_size do
        print_error(
          "#{inspect(name)} queue is full (#{@max_queue_size}). Use await(#{inspect(name)}) first."
        )

        {:error, :queue_full}
      else
        updated_queue = entry.queue ++ [prompt]
        update_agent(name, %{entry | queue: updated_queue})
        position = length(updated_queue)
        print_info("#{inspect(name)}: queued (position #{position})")
        :ok
      end
    else
      # Clean up any completed task before starting new one
      consume_pending_task(name)
      do_send_async(name, prompt)
    end
  end

  @doc """
  Wait for an async agent to finish. Prints the result when done.

  If the agent is already idle, prints a note and returns `:ok`.
  Pass a timeout in milliseconds to avoid blocking forever.

  ## Examples

      cast(:impl, "Work on this")
      # ... later ...
      await(:impl)              # block until done
      await(:impl, 30_000)      # give up after 30 seconds
  """
  @spec await(atom(), timeout()) :: :ok | {:error, term()}
  def await(name, timeout \\ :infinity) do
    entry = get_agent!(name)

    case entry.task do
      nil ->
        if entry.status != :working do
          print_info("#{inspect(name)} is idle.")
        end

        :ok

      task ->
        do_await(name, task, timeout)
    end
  end

  @doc """
  Wait for all busy agents to finish. Prints each result as it arrives.

  ## Example

      cast(:impl, "Implement feature")
      cast(:tests, "Write tests")
      await_all()    # blocks until both are done
  """
  @spec await_all(timeout()) :: :ok
  def await_all(timeout \\ :infinity) do
    busy =
      :ets.tab2list(@table)
      |> Enum.filter(fn {_name, entry} -> entry.task != nil end)
      |> Enum.map(&elem(&1, 0))

    if busy == [] do
      print_info("All agents idle.")
    else
      Enum.each(busy, fn name -> await(name, timeout) end)
    end

    :ok
  end

  # ── Observability ─────────────────────────────────────────────

  @doc """
  Print a status dashboard showing all agents.

  ## Example output

       agent     | status  | task                                 | cost  | turns
      -----------+---------+--------------------------------------+-------+------
       :impl     | working | Implement the caching layer from ... | $0.08 | 3
       :reviewer | idle    |                                      | $0.00 | 0
       :tests    | idle    |                                      | $0.04 | 2
  """
  @spec status() :: [map()]
  def status do
    entries = :ets.tab2list(@table) |> Enum.sort_by(&elem(&1, 0))

    if entries == [] do
      print_info("No agents. Use agent(:name, \"role\") to create one.")
    else
      header = {" agent", "status", "task", "cost", "turns"}

      rows =
        Enum.map(entries, fn {name, e} ->
          {
            " #{inspect(name)}",
            format_status(e),
            truncate(e.task_text || "", 36),
            format_cost(e.cumulative_cost),
            to_string(e.turn_count)
          }
        end)

      print_table(header, rows)
    end

    Enum.map(entries, fn {name, e} ->
      %{
        name: name,
        status: e.status,
        task: e.task_text,
        cost: e.cumulative_cost,
        turns: e.turn_count
      }
    end)
  end

  @doc """
  Get the last response from an agent.

  Returns the response text by default. Pass `:full` to get the
  complete result map (includes cost, session_id, duration, etc.).

  ## Examples

      result(:impl)          # => "Here is the implementation..."
      result(:impl, :full)   # => %{result: "...", cost_usd: 0.04, ...}
  """
  @spec result(atom(), :text | :full) :: String.t() | map() | nil
  def result(name, mode \\ :text)

  def result(name, :full) do
    get_agent!(name).last_result
  end

  def result(name, :text) do
    case get_agent!(name).last_result do
      nil -> nil
      r -> r.result
    end
  end

  @doc """
  Print the conversation history for an agent.

  Shows each turn with its cost and result text. Use `:last` to
  limit output for long conversations.

  ## Examples

      history(:impl)           # full conversation
      history(:impl, last: 3)  # only the last 3 turns
  """
  @spec history(atom(), keyword()) :: :ok
  def history(name, opts \\ []) do
    entry = get_agent!(name)
    turns = entry.backend.history(entry.pid)

    limit = Keyword.get(opts, :last)
    turns = if limit, do: Enum.take(turns, -limit), else: turns

    if turns == [] do
      print_info("#{inspect(name)} has no history.")
    else
      turns
      |> Enum.with_index(1)
      |> Enum.each(&print_turn/1)
    end

    :ok
  end

  @doc """
  Show cost for a single agent. Returns the cost as a float.

  ## Example

      cost(:impl)    # => :impl: $0.12 across 3 turns
  """
  @spec cost(atom()) :: float()
  def cost(name) when is_atom(name) do
    entry = get_agent!(name)

    print_info(
      "#{inspect(name)}: #{format_cost(entry.cumulative_cost)} across #{entry.turn_count} turn#{plural(entry.turn_count)}"
    )

    entry.cumulative_cost
  end

  @doc """
  Show itemized costs for all agents, then print the total.

  ## Example

      cost()
      # :impl: $0.12 (3 turns)
      # :reviewer: $0.24 (1 turn)
      # Total: $0.36
  """
  @spec cost() :: float()
  def cost do
    :ets.tab2list(@table)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.each(fn {name, e} ->
      print_info(
        "#{inspect(name)}: #{format_cost(e.cumulative_cost)} (#{e.turn_count} turn#{plural(e.turn_count)})"
      )
    end)

    total = total_cost()
    print_info("Total: #{format_cost(total)}")
    total
  end

  @doc """
  Get the total cost across all agents as a single number.
  """
  @spec total_cost() :: float()
  def total_cost do
    :ets.tab2list(@table)
    |> Enum.map(fn {_name, e} -> e.cumulative_cost end)
    |> Enum.sum()
  end

  @doc """
  Get detailed info about an agent as a map.

  Returns model, session_id, role, status, cost, turns, and config.

  ## Example

      info(:impl)
      # => %{name: :impl, status: :idle, model: "sonnet", session_id: "abc-123",
      #       cost: 0.04, turns: 1, role: "You write clean code."}
  """
  @spec info(atom()) :: map()
  def info(name) do
    entry = get_agent!(name)

    # Pull session_id from last result if available.
    # Do NOT call backend.session_id — it blocks if the agent is busy.
    session_id =
      case entry.last_result do
        %{session_id: sid} -> sid
        _ -> nil
      end

    %{
      name: name,
      status: entry.status,
      model: Keyword.get(entry.query_opts, :model),
      session_id: session_id,
      role: entry.role,
      cost: entry.cumulative_cost,
      turns: entry.turn_count,
      permission_mode: Keyword.get(entry.query_opts, :permission_mode),
      max_turns: Keyword.get(entry.query_opts, :max_turns),
      allowed_tools: Keyword.get(entry.query_opts, :allowed_tools),
      system_prompt: Keyword.get(entry.query_opts, :system_prompt),
      queue_depth: length(entry.queue)
    }
  end

  # ── Coordination ──────────────────────────────────────────────

  @doc """
  Wait for `from` to finish, then send its last result to `to`.

  The `message` argument frames what `to` should do with the result.
  The forwarded text is appended after your message. Without a message,
  a default framing is used.

  This is synchronous -- it blocks until both agents are done.

  Returns the target agent name on success, so pipes chain:

      ask(:impl, "implement caching")
      |> pipe(:reviewer, "review for edge cases")
      |> pipe(:tests, "write tests for this")

  ## Examples

      # Implement, then review
      ask(:impl, "Implement caching for user lookup")
      pipe(:impl, :reviewer, "Review for cache invalidation edge cases")

      # Or after an async cast
      cast(:impl, "Implement the retry logic")
      # ... do other stuff ...
      pipe(:impl, :tests)   # awaits :impl, sends result to :tests
  """
  @spec pipe(atom() | {:error, term()}, atom(), String.t() | nil) :: atom() | {:error, term()}
  def pipe(from, to, message \\ nil)

  def pipe({:error, _} = err, _to, _message), do: err

  def pipe(from, to, message) when is_atom(from) do
    await(from)
    from_text = result(from)

    if is_nil(from_text) do
      print_error("#{inspect(from)} has no result to pipe.")
      {:error, :no_result}
    else
      text =
        if message do
          "#{message}\n\n#{from_text}"
        else
          "Here is the output from the previous step:\n\n#{from_text}"
        end

      ask(to, text)
    end
  end

  @doc """
  Send the same message to multiple agents in parallel (all via `cast/2`).

  Good for getting multiple perspectives on the same question.

  ## Example

      fan("What issues do you see in lib/myapp/retry.ex?", [:impl, :reviewer])
      # both agents work concurrently
      await_all()
      result(:impl)       # impl's take
      result(:reviewer)   # reviewer's take
  """
  @spec fan(String.t(), [atom()]) :: :ok
  def fan(message, agent_names) when is_list(agent_names) do
    Enum.each(agent_names, fn name -> cast(name, message) end)
    :ok
  end

  # ── Internal: Send ────────────────────────────────────────────

  defp do_send_sync(name, prompt) do
    entry = get_agent!(name)

    case Budget.check(name, entry.cumulative_cost, 0.0) do
      {:error, :budget_exceeded, reason} ->
        print_error(reason)
        {:error, :budget_exceeded}

      :ok ->
        do_send_sync_inner(name, prompt, entry)
    end
  end

  defp do_send_sync_inner(name, prompt, entry) do
    update_agent(name, %{entry | status: :working, task_text: truncate(prompt, 36)})

    IO.puts(IO.ANSI.yellow() <> "#{inspect(name)} working..." <> IO.ANSI.reset())

    start_time = Telemetry.start(:ask, %{agent: name, prompt: prompt})

    Logger.info("[workshop] agent #{inspect(name)} sending message")

    result =
      case entry.timeout do
        nil ->
          entry.backend.send_message(entry.pid, prompt, [])

        timeout ->
          task =
            Task.Supervisor.async_nolink(@tasks_sup, fn ->
              entry.backend.send_message(entry.pid, prompt, [])
            end)

          case Task.yield(task, timeout) || Task.shutdown(task) do
            {:ok, backend_result} -> backend_result
            nil -> {:error, :timeout}
          end
      end

    Logger.info("[workshop] agent #{inspect(name)} got response")

    case result do
      {:ok, r} ->
        cost = r.cost_usd || 0.0
        Telemetry.stop(:ask, start_time, %{cost: cost}, %{agent: name, prompt: prompt})
        PubSub.broadcast({:agent, :ask_complete, name, r})

        current = get_agent!(name)

        update_agent(name, %{
          current
          | status: :idle,
            task_text: nil,
            cumulative_cost: current.cumulative_cost + cost,
            turn_count: current.turn_count + 1,
            last_result: r
        })

        print_result(name, r)
        name

      {:error, reason} = err ->
        Telemetry.error(:ask, start_time, reason, %{agent: name, prompt: prompt})
        PubSub.broadcast({:agent, :error, name, reason})

        current = get_agent!(name)
        update_agent(name, %{current | status: :idle, task_text: nil})
        print_error("#{inspect(name)}: #{inspect(reason)}")
        err
    end
  end

  defp do_send_async(name, prompt) do
    entry = get_agent!(name)

    case Budget.check(name, entry.cumulative_cost, 0.0) do
      {:error, :budget_exceeded, reason} ->
        print_error(reason)
        {:error, :budget_exceeded}

      :ok ->
        do_send_async_inner(name, prompt, entry)
    end
  end

  defp do_send_async_inner(name, prompt, entry) do
    pid = entry.pid
    backend = entry.backend
    agent_name = name

    Telemetry.start(:cast, %{agent: name, prompt: prompt})

    task =
      Task.Supervisor.async_nolink(@tasks_sup, fn ->
        start_time = System.monotonic_time()

        Logger.info("[workshop] agent #{inspect(agent_name)} sending message")

        result =
          try do
            backend.send_message(pid, prompt, [])
          rescue
            e -> {:error, {:crash, Exception.message(e)}}
          end

        Logger.info("[workshop] agent #{inspect(agent_name)} got response")

        record_async_result(agent_name, result, start_time)
        result
      end)

    update_agent(name, %{entry | status: :working, task: task, task_text: truncate(prompt, 36)})
    :ok
  end

  # Update ETS with async task result, then drain the queue.
  # Called from within the task process.
  defp record_async_result(agent_name, {:ok, result}, start_time) do
    cost = result.cost_usd || 0.0
    Telemetry.stop(:cast, start_time, %{cost: cost}, %{agent: agent_name})
    PubSub.broadcast({:agent, :cast_complete, agent_name, result})

    case get_agent(agent_name) do
      nil ->
        :ok

      current ->
        update_agent(agent_name, %{
          current
          | status: :idle,
            cumulative_cost: current.cumulative_cost + cost,
            turn_count: current.turn_count + 1,
            last_result: result
        })

        maybe_drain_queue(agent_name)
    end
  end

  defp record_async_result(agent_name, {:error, reason}, start_time) do
    Telemetry.error(:cast, start_time, reason, %{agent: agent_name})
    PubSub.broadcast({:agent, :error, agent_name, reason})

    case get_agent(agent_name) do
      nil ->
        :ok

      current ->
        update_agent(agent_name, %{current | status: :idle})
        maybe_drain_queue(agent_name)
    end
  end

  # If there are queued messages, start the next one as an async task.
  defp maybe_drain_queue(agent_name) do
    case get_agent(agent_name) do
      nil ->
        :ok

      %{queue: []} ->
        :ok

      %{queue: [next | rest]} = entry ->
        update_agent(agent_name, %{entry | queue: rest})
        do_send_async(agent_name, next)
    end
  end

  defp do_await(name, task, timeout) do
    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, {:ok, result}} ->
        current = get_agent!(name)
        update_agent(name, %{current | task: nil, task_text: nil})
        print_result(name, result)
        :ok

      {:ok, {:error, reason}} ->
        current = get_agent!(name)
        update_agent(name, %{current | task: nil, task_text: nil, status: :idle})
        print_error("#{inspect(name)}: #{inspect(reason)}")
        {:error, reason}

      nil ->
        current = get_agent!(name)
        update_agent(name, %{current | task: nil, task_text: nil, status: :idle})
        print_error("#{inspect(name)}: timed out")
        {:error, :timeout}

      {:exit, reason} ->
        current = get_agent!(name)
        update_agent(name, %{current | task: nil, task_text: nil, status: :idle})
        print_error("#{inspect(name)}: #{inspect(reason)}")
        {:error, {:exit, reason}}
    end
  end

  # Consume any pending async task (finished or still running).
  # Used before synchronous sends to avoid stale task state.
  defp consume_pending_task(name) do
    entry = get_agent!(name)

    case entry.task do
      nil ->
        :ok

      task ->
        Task.yield(task, :infinity) || Task.shutdown(task)
        current = get_agent!(name)
        update_agent(name, %{current | task: nil, task_text: nil, status: :idle})
    end
  end

  # ── Internal: Registry ────────────────────────────────────────

  defp get_global_state do
    %{
      backend: :persistent_term.get({AgentWorkshop, :backend}, nil),
      backend_config: :persistent_term.get({AgentWorkshop, :backend_config}, nil),
      query_opts: :persistent_term.get({AgentWorkshop, :query_opts}, permission_mode: :auto),
      context: :persistent_term.get({AgentWorkshop, :context}, nil)
    }
  end

  defp get_agent(name) do
    case :ets.lookup(@table, name) do
      [{^name, entry}] -> entry
      [] -> nil
    end
  end

  defp get_agent!(name) do
    case get_agent(name) do
      nil ->
        raise ArgumentError,
              "unknown agent #{inspect(name)}. Use agent(#{inspect(name)}) to create one."

      entry ->
        entry
    end
  end

  defp update_agent(name, entry) do
    :ets.insert(@table, {name, entry})
  end

  # Stop an agent's processes with escalating force:
  # 1. Try graceful stop (3 second timeout)
  # 2. If that fails, kill the process directly
  defp force_stop_agent(entry) do
    # Kill any async task first
    if entry.task do
      try do
        Task.Supervisor.terminate_child(@tasks_sup, entry.task.pid)
      catch
        :exit, _ -> :ok
      end
    end

    # Try graceful stop with short timeout
    pid = entry.pid

    try do
      GenServer.stop(pid, :normal, 3_000)
    catch
      :exit, _ ->
        # Graceful stop failed — force kill
        if Process.alive?(pid), do: Process.exit(pid, :kill)
    end

    # Clean up from DynamicSupervisor
    try do
      DynamicSupervisor.terminate_child(@sessions_sup, pid)
    catch
      :exit, _ -> :ok
    end
  end

  defp write_workshop_mcp_config do
    port =
      if Code.ensure_loaded?(AgentWorkshop.MCP) do
        :persistent_term.get({AgentWorkshop.MCP, :port}, 4222)
      else
        4222
      end

    config = %{
      "mcpServers" => %{
        "workshop" => %{
          "type" => "http",
          "url" => "http://localhost:#{port}/mcp"
        }
      }
    }

    path = Path.join(System.tmp_dir!(), "workshop_mcp_#{:erlang.phash2(self())}.json")
    File.write!(path, Jason.encode!(config))
    path
  end

  # ── Internal: Helpers ─────────────────────────────────────────

  defp split_opts(opts) do
    Keyword.drop(opts, @special_keys)
  end

  defp validate_opts!(opts) do
    case Keyword.fetch(opts, :permission_mode) do
      {:ok, mode} when mode not in @valid_permission_modes ->
        raise ArgumentError,
              "invalid permission_mode #{inspect(mode)}. " <>
                "Valid modes: #{inspect(@valid_permission_modes)}"

      _ ->
        :ok
    end
  end

  defp compose_system_prompt(skill_context, user_context, role) do
    [skill_context, user_context, role]
    |> Enum.reject(fn s -> is_nil(s) or String.trim(s) == "" end)
    |> case do
      [] -> nil
      parts -> Enum.join(parts, "\n\n")
    end
  end

  # ── Internal: Display (delegated to AgentWorkshop.Workshop.Display) ──

  defp print_result(name, result), do: Display.print_result(name, result)
  defp print_error(msg), do: Display.print_error(msg)
  defp print_info(msg), do: Display.print_info(msg)
  defp format_status(entry), do: Display.format_status(entry)
  defp format_cost(amount), do: Display.format_cost(amount)
  defp truncate(str, max), do: Display.truncate(str, max)
  defp plural(n), do: Display.plural(n)
  defp print_event(entry), do: Display.print_event(entry)
  defp print_profile(data), do: Display.print_profile(data)
  defp print_work_item(item), do: Display.print_work_item(item)
  defp print_worker_info(info), do: Display.print_worker_info(info)
  defp print_schedule_info(info), do: Display.print_schedule_info(info)
  defp format_interval(ms), do: Display.format_interval(ms)
  defp print_turn(data), do: Display.print_turn(data)
  defp print_table(header, rows), do: Display.print_table(header, rows)
end
