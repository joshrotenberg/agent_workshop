defmodule AgentWorkshop.CLI do
  @moduledoc false

  use Cheer.Command

  @daemon AgentWorkshop.Application.daemon_node()

  command "aw" do
    about("AgentWorkshop -- multi-agent orchestration")

    subcommand(AgentWorkshop.CLI.Daemon)
    subcommand(AgentWorkshop.CLI.Stop)
    subcommand(AgentWorkshop.CLI.Status)
    subcommand(AgentWorkshop.CLI.Board)
    subcommand(AgentWorkshop.CLI.Workers)
    subcommand(AgentWorkshop.CLI.Workflows)
    subcommand(AgentWorkshop.CLI.Cost)
    subcommand(AgentWorkshop.CLI.Events)
    subcommand(AgentWorkshop.CLI.Load)
    subcommand(AgentWorkshop.CLI.Console)
  end

  @doc false
  def mode do
    case Process.get(:aw_mode) do
      nil ->
        detected = AgentWorkshop.Application.try_connect_daemon()
        Process.put(:aw_mode, detected)
        detected

      m ->
        m
    end
  end

  @doc false
  def call(mod, fun, args) do
    case mode() do
      :local -> apply(mod, fun, args)
      :remote -> :erpc.call(@daemon, mod, fun, args)
    end
  end
end

# ── Daemon ─────────────────────────────────────────────────

defmodule AgentWorkshop.CLI.Daemon do
  @moduledoc false
  use Cheer.Command

  command "daemon" do
    about("Start the background daemon")
  end

  @impl Cheer.Command
  def run(_args, _raw) do
    # Daemon startup is handled by Application.start routing.
    # If we get here, we're already inside the daemon process.
    IO.puts("aw daemon running (#{node()})")
  end
end

# ── Stop ───────────────────────────────────────────────────

defmodule AgentWorkshop.CLI.Stop do
  @moduledoc false
  use Cheer.Command

  @daemon AgentWorkshop.Application.daemon_node()

  command "stop" do
    about("Stop the daemon")
  end

  @impl Cheer.Command
  def run(_args, _raw) do
    case AgentWorkshop.CLI.mode() do
      :local ->
        IO.puts("No daemon running.")

      :remote ->
        :erpc.call(@daemon, File, :rm, [AgentWorkshop.Application.pid_file()])
        :erpc.call(@daemon, System, :stop, [0])
        IO.puts("Daemon stopped.")
    end
  end
end

# ── Status ─────────────────────────────────────────────────

defmodule AgentWorkshop.CLI.Status do
  @moduledoc false
  use Cheer.Command

  @daemon AgentWorkshop.Application.daemon_node()

  command "status" do
    about("Show agent status")
  end

  @impl Cheer.Command
  def run(_args, _raw) do
    case AgentWorkshop.CLI.mode() do
      :remote ->
        uptime =
          :erpc.call(@daemon, :erlang, :statistics, [:wall_clock]) |> elem(0) |> div(1000)

        memory = :erpc.call(@daemon, :erlang, :memory, [:total])
        IO.puts("Mode:   daemon (#{@daemon})")
        IO.puts("Uptime: #{format_uptime(uptime)}")
        IO.puts("Memory: #{div(memory, 1_048_576)} MB")
        IO.puts("")

      :local ->
        IO.puts("Mode:   local (no daemon)")
        IO.puts("")
    end

    AgentWorkshop.CLI.call(AgentWorkshop.Workshop, :status, [])
    :ok
  end

  defp format_uptime(seconds) do
    cond do
      seconds < 60 -> "#{seconds}s"
      seconds < 3600 -> "#{div(seconds, 60)}m #{rem(seconds, 60)}s"
      true -> "#{div(seconds, 3600)}h #{div(rem(seconds, 3600), 60)}m"
    end
  end
end

# ── Board ──────────────────────────────────────────────────

defmodule AgentWorkshop.CLI.Board do
  @moduledoc false
  use Cheer.Command

  command "board" do
    about("Show work board")
  end

  @impl Cheer.Command
  def run(_args, _raw) do
    AgentWorkshop.CLI.call(AgentWorkshop.Workshop, :board, [[]])
    :ok
  end
end

# ── Workers ────────────────────────────────────────────────

defmodule AgentWorkshop.CLI.Workers do
  @moduledoc false
  use Cheer.Command

  command "workers" do
    about("Show board worker status")
  end

  @impl Cheer.Command
  def run(_args, _raw) do
    AgentWorkshop.CLI.call(AgentWorkshop.Workshop, :workers, [])
    :ok
  end
end

# ── Workflows ──────────────────────────────────────────────

defmodule AgentWorkshop.CLI.Workflows do
  @moduledoc false
  use Cheer.Command

  command "workflows" do
    about("Show workflow status")
  end

  @impl Cheer.Command
  def run(_args, _raw) do
    AgentWorkshop.CLI.call(AgentWorkshop.Workshop, :workflows, [])
    :ok
  end
end

# ── Cost ───────────────────────────────────────────────────

defmodule AgentWorkshop.CLI.Cost do
  @moduledoc false
  use Cheer.Command

  command "cost" do
    about("Show cost breakdown")
  end

  @impl Cheer.Command
  def run(_args, _raw) do
    AgentWorkshop.CLI.call(AgentWorkshop.Workshop, :cost, [])
    :ok
  end
end

# ── Events ─────────────────────────────────────────────────

defmodule AgentWorkshop.CLI.Events do
  @moduledoc false
  use Cheer.Command

  command "events" do
    about("Show recent events")
  end

  @impl Cheer.Command
  def run(_args, _raw) do
    AgentWorkshop.CLI.call(AgentWorkshop.Workshop, :events, [[]])
    :ok
  end
end

# ── Load ───────────────────────────────────────────────────

defmodule AgentWorkshop.CLI.Load do
  @moduledoc false
  use Cheer.Command

  command "load" do
    about("Load a .workshop.exs config file")
    argument(:file, type: :string, required: false, help: "Path to config file")
  end

  @impl Cheer.Command
  def run(%{file: file}, _raw) do
    path = file || ".workshop.exs"

    case AgentWorkshop.CLI.call(AgentWorkshop.Workshop, :load, [path]) do
      :ok -> :ok
      {:error, reason} -> IO.puts("Error: #{inspect(reason)}")
    end
  end
end

# ── Console ────────────────────────────────────────────────

defmodule AgentWorkshop.CLI.Console do
  @moduledoc false
  use Cheer.Command

  @daemon AgentWorkshop.Application.daemon_node()

  @iex_init """
  Node.connect(:"#{AgentWorkshop.Application.daemon_node()}")
  import AgentWorkshop.Workshop

  IEx.configure(
    default_prompt: "aw> ",
    alive_prompt: "aw> "
  )

  IO.puts("\\nAgentWorkshop console -- import AgentWorkshop.Workshop is loaded\\n")
  """

  command "console" do
    about("Print iex args (usage: iex $(aw console))")
  end

  @impl Cheer.Command
  def run(_args, _raw) do
    case AgentWorkshop.CLI.mode() do
      :local ->
        IO.puts("Error: console requires a running daemon. Start one with: aw daemon")

      :remote ->
        cookie = Atom.to_string(AgentWorkshop.Application.cookie())
        sname = "aw_console_#{System.system_time(:nanosecond)}"

        dot_iex = Path.join(System.tmp_dir!(), ".aw.iex.exs")
        File.write!(dot_iex, @iex_init)

        ebin_args = ebin_pa_args()

        IO.write("--sname #{sname}@localhost --cookie #{cookie} --dot-iex #{dot_iex}#{ebin_args}")
    end
  end

  defp ebin_pa_args do
    paths =
      :erpc.call(@daemon, :code, :get_path, [])
      |> Enum.map(&to_string/1)
      |> Enum.filter(&String.contains?(&1, "agent_workshop"))

    case paths do
      [] -> ""
      ps -> " " <> Enum.map_join(ps, " ", &"-pa #{&1}")
    end
  end
end
