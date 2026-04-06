defmodule AgentWorkshop.Application do
  @moduledoc false
  use Application

  # Supervision tree start order matters:
  #
  #   1. TableManager   -- must be first; creates and owns all ETS tables so
  #                        that every downstream process can read/write on init.
  #   2. Global config  -- :persistent_term defaults (backend, query_opts, context).
  #                        No process needed; reads are free.
  #   3. Registries     -- PubSub (duplicate keys for fan-out), Scheduler and
  #                        BoardWorker (unique keys for named lookup).
  #   4. EventLog       -- subscribes to the PubSub registry on init, so the
  #                        registry must already be running.
  #   5. Persistence    -- subscribes to PubSub; writes state to disk on change.
  #                        Idle until enabled via configure(persistence: ...).
  #   6. ProcessMonitor -- monitors agent SessionServer pids; auto-cleans
  #                        ETS entries when agents crash.
  #   7. DynamicSupervisor / TaskSupervisor -- started last because nothing
  #                        depends on them at boot; agents are added later via
  #                        Workshop.agent/2.

  # Dialyzer can't see runtime-only Burrito code paths. These functions
  # are only reachable when running inside a Burrito binary.
  @dialyzer [
    {:nowarn_function, start_daemon: 0},
    {:nowarn_function, daemonize: 0},
    {:nowarn_function, start_client: 1},
    {:nowarn_function, burrito_bin_path: 0},
    {:nowarn_function, await_daemon: 1}
  ]

  @burrito_args Burrito.Util.Args
  @pid_file Path.join(System.tmp_dir!(), "aw.pid")
  @daemon_node :aw@localhost
  @cookie :aw_workshop

  def start(_type, _args) do
    case cli_mode() do
      {:daemon, true} -> start_daemon()
      {:daemon, false} -> daemonize()
      {:client, args} -> start_client(args)
      :library -> start_library()
    end
  end

  # Library mode: standard OTP application (iex -S mix or as a dependency)
  defp start_library do
    AgentWorkshop.Workshop.init_global_state()

    children = supervision_children()

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: AgentWorkshop.Supervisor
    )
  end

  # Daemon mode: named node with full supervision tree + MCP + dashboard
  defp start_daemon do
    Node.start(@daemon_node, :shortnames)
    Node.set_cookie(@cookie)
    File.write!(@pid_file, :os.getpid())

    AgentWorkshop.Workshop.init_global_state()

    children = supervision_children()

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: AgentWorkshop.Supervisor
    )
  end

  # Launch: re-exec self backgrounded, then exit
  defp daemonize do
    check_node = :"aw_check_#{System.system_time(:nanosecond)}@localhost"
    Node.start(check_node, :shortnames)
    Node.set_cookie(@cookie)

    if Node.connect(@daemon_node) do
      IO.puts("aw daemon is already running.")
      System.halt(0)
    end

    Node.stop()

    case burrito_bin_path() do
      nil ->
        IO.puts("Dev mode: run with AW_DAEMON=1 mix run --no-halt -- daemon")
        System.halt(1)

      bin ->
        cmd = ~s(AW_DAEMON=1 nohup "#{bin}" daemon > /dev/null 2>&1 & echo $!)
        # credo:disable-for-next-line Credo.Check.Warning.UnsafeExec
        :os.cmd(String.to_charlist(cmd))
        IO.puts("aw daemon launching...")

        client = :"aw_check_#{System.system_time(:nanosecond)}@localhost"
        Node.start(client, :shortnames)
        Node.set_cookie(@cookie)

        case await_daemon(10) do
          :ok -> IO.puts("aw daemon started (pid file: #{@pid_file})")
          :timeout -> IO.puts("Warning: daemon may not have started correctly")
        end

        System.halt(0)
    end
  end

  # Client mode: connect to daemon via erpc, run CLI command, exit
  defp start_client(args) do
    client = :"aw_cli_#{System.system_time(:nanosecond)}@localhost"
    Node.start(client, :shortnames)
    Node.set_cookie(@cookie)

    mode =
      case Node.connect(@daemon_node) do
        true -> :remote
        false -> :local
      end

    if mode == :local do
      AgentWorkshop.Workshop.init_global_state()

      children = supervision_children()

      {:ok, _} =
        Supervisor.start_link(children,
          strategy: :one_for_one,
          name: AgentWorkshop.Supervisor
        )
    end

    Process.put(:aw_mode, mode)
    Cheer.run(AgentWorkshop.CLI, args, prog: "aw")

    System.halt(0)
  end

  # Detect which mode to run in.
  # Only enter CLI mode when running inside a Burrito binary OR when
  # AW_DAEMON=1 is set (dev mode daemon). Otherwise, library mode.
  defp cli_mode do
    cond do
      System.get_env("AW_DAEMON") == "1" ->
        {:daemon, true}

      in_burrito?() ->
        args = @burrito_args.argv()

        case args do
          ["daemon"] -> {:daemon, false}
          cli_args -> {:client, cli_args}
        end

      true ->
        :library
    end
  end

  defp in_burrito? do
    Code.ensure_loaded?(@burrito_args) and
      @burrito_args.get_bin_path() != :not_in_burrito
  end

  defp burrito_bin_path do
    if in_burrito?() do
      @burrito_args.get_bin_path()
    else
      nil
    end
  end

  defp await_daemon(0), do: :timeout

  defp await_daemon(remaining) do
    case Node.connect(@daemon_node) do
      true ->
        :ok

      false ->
        Process.sleep(500)
        await_daemon(remaining - 1)
    end
  end

  defp supervision_children do
    [
      AgentWorkshop.TableManager,
      {Registry, keys: :duplicate, name: AgentWorkshop.PubSub.Registry},
      {Registry, keys: :unique, name: AgentWorkshop.Scheduler.Registry},
      {Registry, keys: :unique, name: AgentWorkshop.BoardWorker.Registry},
      AgentWorkshop.EventLog,
      AgentWorkshop.Persistence,
      AgentWorkshop.ProcessMonitor,
      {DynamicSupervisor,
       name: AgentWorkshop.Workshop.SessionsSupervisor, strategy: :one_for_one},
      {Task.Supervisor, name: AgentWorkshop.Workshop.TasksSupervisor}
    ]
  end

  def pid_file, do: @pid_file
  def daemon_node, do: @daemon_node
  def cookie, do: @cookie
end
