if Code.ensure_loaded?(Anubis.Server) do
  # ── Tool Components ─────────────────────────────────────────

  defmodule AgentWorkshop.MCP.Tools.Configure do
    @moduledoc false
    use Anubis.Server.Component, type: :tool
    alias Anubis.Server.Response

    schema do
      field(:model, :string, description: "default model (e.g. sonnet, opus, haiku)")

      field(:context, :string,
        description: "global system prompt prepended to every agent's role"
      )

      field(:permission_mode, :string,
        description: "permission mode (auto, bypass_permissions, default)"
      )
    end

    @impl true
    def execute(params, frame) do
      opts =
        params
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Enum.map(fn
          {:permission_mode, v} -> {:permission_mode, String.to_existing_atom(v)}
          pair -> pair
        end)

      AgentWorkshop.Workshop.configure(opts)
      {:reply, Response.text(Response.tool(), "Configured."), frame}
    end
  end

  defmodule AgentWorkshop.MCP.Tools.CreateAgent do
    @moduledoc false
    use Anubis.Server.Component, type: :tool
    alias Anubis.Server.Response

    schema do
      field(:name, :string,
        required: true,
        description: "agent name (e.g. impl, reviewer, tests)"
      )

      field(:role, :string, description: "role description / agent-specific system prompt")
      field(:model, :string, description: "model override for this agent")
      field(:max_turns, :integer, description: "max conversation turns per send")

      field(:permission_mode, :string,
        description: "permission mode (auto, bypass_permissions, default)"
      )

      field(:allowed_tools, {:list, :string},
        description: "list of allowed tools (e.g. Read, Bash)"
      )
    end

    @impl true
    def execute(%{name: name} = params, frame) do
      atom_name = String.to_atom(name)
      role = Map.get(params, :role)

      opts =
        params
        |> Map.drop([:name, :role])
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Enum.map(fn
          {:permission_mode, v} -> {:permission_mode, String.to_existing_atom(v)}
          pair -> pair
        end)

      AgentWorkshop.Workshop.agent(atom_name, role, opts)
      {:reply, Response.text(Response.tool(), "Agent #{name} created."), frame}
    end
  end

  defmodule AgentWorkshop.MCP.Tools.Ask do
    @moduledoc false
    use Anubis.Server.Component, type: :tool
    alias Anubis.Server.Response

    schema do
      field(:agent, :string, required: true, description: "agent name")
      field(:prompt, :string, required: true, description: "message to send")
    end

    @impl true
    def execute(%{agent: name, prompt: prompt}, frame) do
      atom_name = String.to_existing_atom(name)

      case AgentWorkshop.Workshop.ask(atom_name, prompt) do
        {:error, reason} ->
          {:reply, Response.error(Response.tool(), inspect(reason)), frame}

        _name ->
          text = AgentWorkshop.Workshop.result(atom_name) || "(no response)"
          {:reply, Response.text(Response.tool(), text), frame}
      end
    end
  end

  defmodule AgentWorkshop.MCP.Tools.Cast do
    @moduledoc false
    use Anubis.Server.Component, type: :tool
    alias Anubis.Server.Response

    schema do
      field(:agent, :string, required: true, description: "agent name")
      field(:prompt, :string, required: true, description: "message to send asynchronously")
    end

    @impl true
    def execute(%{agent: name, prompt: prompt}, frame) do
      atom_name = String.to_existing_atom(name)

      case AgentWorkshop.Workshop.cast(atom_name, prompt) do
        :ok ->
          {:reply,
           Response.text(Response.tool(), "Cast to #{name}. Use await to get the result."), frame}

        {:error, reason} ->
          {:reply, Response.error(Response.tool(), inspect(reason)), frame}
      end
    end
  end

  defmodule AgentWorkshop.MCP.Tools.Await do
    @moduledoc false
    use Anubis.Server.Component, type: :tool
    alias Anubis.Server.Response

    schema do
      field(:agent, :string, required: true, description: "agent name to wait for")

      field(:timeout, :integer,
        description: "max milliseconds to wait (default: 120000). 0 to just check status."
      )
    end

    @impl true
    def execute(%{agent: name} = params, frame) do
      atom_name = String.to_existing_atom(name)
      timeout = Map.get(params, :timeout, 120_000)

      info = AgentWorkshop.Workshop.info(atom_name)

      if info.status == :idle do
        text = AgentWorkshop.Workshop.result(atom_name) || "(no result yet)"
        {:reply, Response.text(Response.tool(), text), frame}
      else
        if timeout == 0 do
          {:reply,
           Response.text(
             Response.tool(),
             "#{name} is still working. Call await again later, or use status to check."
           ), frame}
        else
          AgentWorkshop.Workshop.await(atom_name, timeout)
          text = AgentWorkshop.Workshop.result(atom_name) || "(no result)"
          {:reply, Response.text(Response.tool(), text), frame}
        end
      end
    end
  end

  defmodule AgentWorkshop.MCP.Tools.AwaitAll do
    @moduledoc false
    use Anubis.Server.Component, type: :tool
    alias Anubis.Server.Response

    schema do
      field(:timeout, :integer,
        description: "max milliseconds to wait per agent (default: 120000). 0 to just check."
      )
    end

    @impl true
    def execute(params, frame) do
      timeout = Map.get(params, :timeout, 120_000)
      agents = AgentWorkshop.Workshop.agents()

      any_busy? =
        Enum.any?(agents, fn name ->
          AgentWorkshop.Workshop.info(name).status == :working
        end)

      if any_busy? and timeout > 0 do
        AgentWorkshop.Workshop.await_all(timeout)
      end

      results = collect_results(agents)
      {:reply, Response.text(Response.tool(), results), frame}
    end

    defp collect_results(agents) do
      Enum.map_join(agents, "\n\n", fn name ->
        info = AgentWorkshop.Workshop.info(name)
        status = if info.status == :working, do: " (still working)", else: ""
        text = AgentWorkshop.Workshop.result(name)
        "## #{name}#{status}\n#{text || "(no result yet)"}"
      end)
    end
  end

  defmodule AgentWorkshop.MCP.Tools.Status do
    @moduledoc false
    use Anubis.Server.Component, type: :tool
    alias Anubis.Server.Response

    schema do
    end

    @impl true
    def execute(_params, frame) do
      agents = AgentWorkshop.Workshop.agents()

      if agents == [] do
        {:reply, Response.text(Response.tool(), "No agents."), frame}
      else
        lines =
          Enum.map_join(agents, "\n", fn name ->
            info = AgentWorkshop.Workshop.info(name)
            status = info.status
            model = info.model || "default"
            cost = info.cost
            turns = info.turns
            "#{name}: #{status} | model=#{model} | $#{Float.round(cost, 2)} | #{turns} turns"
          end)

        {:reply, Response.text(Response.tool(), lines), frame}
      end
    end
  end

  defmodule AgentWorkshop.MCP.Tools.Result do
    @moduledoc false
    use Anubis.Server.Component, type: :tool
    alias Anubis.Server.Response

    schema do
      field(:agent, :string, required: true, description: "agent name")
    end

    @impl true
    def execute(%{agent: name}, frame) do
      atom_name = String.to_existing_atom(name)
      text = AgentWorkshop.Workshop.result(atom_name) || "(no result)"
      {:reply, Response.text(Response.tool(), text), frame}
    end
  end

  defmodule AgentWorkshop.MCP.Tools.Pipe do
    @moduledoc false
    use Anubis.Server.Component, type: :tool
    alias Anubis.Server.Response

    schema do
      field(:from, :string, required: true, description: "source agent name")
      field(:to, :string, required: true, description: "target agent name")
      field(:message, :string, description: "framing message for what the target should do")
    end

    @impl true
    def execute(%{from: from, to: to} = params, frame) do
      from_atom = String.to_existing_atom(from)
      to_atom = String.to_existing_atom(to)
      message = Map.get(params, :message)

      case AgentWorkshop.Workshop.pipe(from_atom, to_atom, message) do
        {:error, reason} ->
          {:reply, Response.error(Response.tool(), inspect(reason)), frame}

        _name ->
          text = AgentWorkshop.Workshop.result(to_atom) || "(no result)"
          {:reply, Response.text(Response.tool(), text), frame}
      end
    end
  end

  defmodule AgentWorkshop.MCP.Tools.Fan do
    @moduledoc false
    use Anubis.Server.Component, type: :tool
    alias Anubis.Server.Response

    schema do
      field(:message, :string, required: true, description: "message to send to all agents")
      field(:agents, {:list, :string}, required: true, description: "list of agent names")
    end

    @impl true
    def execute(%{message: message, agents: agents}, frame) do
      atom_names = Enum.map(agents, &String.to_existing_atom/1)
      AgentWorkshop.Workshop.fan(message, atom_names)
      names = Enum.join(agents, ", ")

      {:reply, Response.text(Response.tool(), "Sent to #{names}. Use await_all to collect."),
       frame}
    end
  end

  defmodule AgentWorkshop.MCP.Tools.Info do
    @moduledoc false
    use Anubis.Server.Component, type: :tool
    alias Anubis.Server.Response

    schema do
      field(:agent, :string, required: true, description: "agent name")
    end

    @impl true
    def execute(%{agent: name}, frame) do
      atom_name = String.to_existing_atom(name)
      info = AgentWorkshop.Workshop.info(atom_name)
      {:reply, Response.json(Response.tool(), info), frame}
    end
  end

  defmodule AgentWorkshop.MCP.Tools.Agents do
    @moduledoc false
    use Anubis.Server.Component, type: :tool
    alias Anubis.Server.Response

    schema do
    end

    @impl true
    def execute(_params, frame) do
      agents = AgentWorkshop.Workshop.agents()
      text = if agents == [], do: "No agents.", else: Enum.map_join(agents, ", ", &to_string/1)
      {:reply, Response.text(Response.tool(), text), frame}
    end
  end

  defmodule AgentWorkshop.MCP.Tools.Reset do
    @moduledoc false
    use Anubis.Server.Component, type: :tool
    alias Anubis.Server.Response

    schema do
      field(:agent, :string, required: true, description: "agent name to reset")
    end

    @impl true
    def execute(%{agent: name}, frame) do
      atom_name = String.to_existing_atom(name)
      AgentWorkshop.Workshop.reset(atom_name)
      {:reply, Response.text(Response.tool(), "Agent #{name} reset."), frame}
    end
  end

  defmodule AgentWorkshop.MCP.Tools.Dismiss do
    @moduledoc false
    use Anubis.Server.Component, type: :tool
    alias Anubis.Server.Response

    schema do
      field(:agent, :string, required: true, description: "agent name to remove")
    end

    @impl true
    def execute(%{agent: name}, frame) do
      atom_name = String.to_existing_atom(name)
      AgentWorkshop.Workshop.dismiss(atom_name)
      {:reply, Response.text(Response.tool(), "Agent #{name} dismissed."), frame}
    end
  end

  defmodule AgentWorkshop.MCP.Tools.Cost do
    @moduledoc false
    use Anubis.Server.Component, type: :tool
    alias Anubis.Server.Response

    schema do
    end

    @impl true
    def execute(_params, frame) do
      agents = AgentWorkshop.Workshop.agents()

      lines =
        Enum.map_join(agents, "\n", fn name ->
          info = AgentWorkshop.Workshop.info(name)
          "#{name}: $#{Float.round(info.cost, 2)} (#{info.turns} turns)"
        end)

      total = AgentWorkshop.Workshop.total_cost()
      text = if lines == "", do: "No agents.", else: "#{lines}\nTotal: $#{Float.round(total, 2)}"
      {:reply, Response.text(Response.tool(), text), frame}
    end
  end

  # ── Work Board Tools ─────────────────────────────────────────

  defmodule AgentWorkshop.MCP.Tools.AddWork do
    @moduledoc false
    use Anubis.Server.Component, type: :tool
    alias Anubis.Server.Response

    schema do
      field(:id, :string, required: true, description: "work item ID")
      field(:title, :string, required: true, description: "work item title")
      field(:type, :string, description: "work type: code, review, test, docs, deploy, triage")
      field(:spec, :string, description: "detailed specification")
      field(:priority, :integer, description: "1 (highest) to 5 (lowest), default 3")
      field(:depends_on, {:list, :string}, description: "list of work item IDs to depend on")
    end

    @impl true
    def execute(%{id: id, title: title} = params, frame) do
      opts =
        params
        |> Map.drop([:id, :title])
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Enum.map(fn
          {:type, v} -> {:type, String.to_existing_atom(v)}
          {:depends_on, ids} -> {:depends_on, Enum.map(ids, &String.to_atom/1)}
          pair -> pair
        end)

      AgentWorkshop.Workshop.work(String.to_atom(id), title, opts)
      {:reply, Response.text(Response.tool(), "Work item #{id} added."), frame}
    end
  end

  defmodule AgentWorkshop.MCP.Tools.Board do
    @moduledoc false
    use Anubis.Server.Component, type: :tool
    alias Anubis.Server.Response

    schema do
      field(:status, :string,
        description: "filter by status: new, ready, claimed, in_progress, done, failed, blocked"
      )

      field(:type, :string, description: "filter by type: code, review, test, docs")
    end

    @impl true
    def execute(params, frame) do
      filters =
        params
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Enum.map(fn {k, v} -> {k, String.to_existing_atom(v)} end)

      text = format_board(AgentWorkshop.Work.list(filters))
      {:reply, Response.text(Response.tool(), text), frame}
    end

    defp format_board([]), do: "Board is empty."

    defp format_board(items) do
      Enum.map_join(items, "\n", fn item ->
        claimed = if item.claimed_by, do: " (#{item.claimed_by})", else: ""
        deps = if item.depends_on != [], do: " deps:#{inspect(item.depends_on)}", else: ""
        "[#{item.status}] #{item.id} - #{item.title} [#{item.type}]#{claimed}#{deps}"
      end)
    end
  end

  defmodule AgentWorkshop.MCP.Tools.ClaimWork do
    @moduledoc false
    use Anubis.Server.Component, type: :tool
    alias Anubis.Server.Response

    schema do
      field(:id, :string, required: true, description: "work item ID to claim")
      field(:agent, :string, required: true, description: "agent name claiming the work")
    end

    @impl true
    def execute(%{id: id, agent: agent}, frame) do
      case AgentWorkshop.Work.claim(String.to_existing_atom(id), String.to_existing_atom(agent)) do
        :ok -> {:reply, Response.text(Response.tool(), "#{agent} claimed #{id}."), frame}
        {:error, reason} -> {:reply, Response.error(Response.tool(), inspect(reason)), frame}
      end
    end
  end

  defmodule AgentWorkshop.MCP.Tools.CompleteWork do
    @moduledoc false
    use Anubis.Server.Component, type: :tool
    alias Anubis.Server.Response

    schema do
      field(:id, :string, required: true, description: "work item ID to complete")
      field(:result, :string, description: "result summary")
    end

    @impl true
    def execute(%{id: id} = params, frame) do
      result = Map.get(params, :result)

      case AgentWorkshop.Work.complete(String.to_existing_atom(id), result) do
        :ok -> {:reply, Response.text(Response.tool(), "#{id} completed."), frame}
        {:error, reason} -> {:reply, Response.error(Response.tool(), inspect(reason)), frame}
      end
    end
  end

  defmodule AgentWorkshop.MCP.Tools.FailWork do
    @moduledoc false
    use Anubis.Server.Component, type: :tool
    alias Anubis.Server.Response

    schema do
      field(:id, :string, required: true, description: "work item ID that failed")
      field(:error, :string, description: "error description")
    end

    @impl true
    def execute(%{id: id} = params, frame) do
      error = Map.get(params, :error)

      case AgentWorkshop.Work.fail(String.to_existing_atom(id), error) do
        :ok -> {:reply, Response.text(Response.tool(), "#{id} marked as failed."), frame}
        {:error, reason} -> {:reply, Response.error(Response.tool(), inspect(reason)), frame}
      end
    end
  end

  defmodule AgentWorkshop.MCP.Tools.FromProfile do
    @moduledoc false
    use Anubis.Server.Component, type: :tool
    alias Anubis.Server.Response

    schema do
      field(:profile, :string, required: true, description: "profile name to instantiate")
      field(:name, :string, required: true, description: "name for the new agent")
    end

    @impl true
    def execute(%{profile: profile, name: name}, frame) do
      AgentWorkshop.Workshop.from_profile(
        String.to_existing_atom(profile),
        String.to_atom(name)
      )

      {:reply, Response.text(Response.tool(), "Agent #{name} created from profile #{profile}."),
       frame}
    rescue
      e -> {:reply, Response.error(Response.tool(), Exception.message(e)), frame}
    end
  end

  # ── Server ──────────────────────────────────────────────────

  defmodule AgentWorkshop.MCP.Server do
    @moduledoc """
    MCP server exposing Workshop functions as tools.

    Allows a Claude Code session (or any MCP client) to orchestrate
    Workshop agents running in the same BEAM node.
    """

    use Anubis.Server,
      name: "agent-workshop",
      version: "0.1.0",
      capabilities: [:tools]

    component(AgentWorkshop.MCP.Tools.Configure)
    component(AgentWorkshop.MCP.Tools.CreateAgent)
    component(AgentWorkshop.MCP.Tools.Ask)
    component(AgentWorkshop.MCP.Tools.Cast)
    component(AgentWorkshop.MCP.Tools.Await)
    component(AgentWorkshop.MCP.Tools.AwaitAll)
    component(AgentWorkshop.MCP.Tools.Status)
    component(AgentWorkshop.MCP.Tools.Result)
    component(AgentWorkshop.MCP.Tools.Pipe)
    component(AgentWorkshop.MCP.Tools.Fan)
    component(AgentWorkshop.MCP.Tools.Info)
    component(AgentWorkshop.MCP.Tools.Agents)
    component(AgentWorkshop.MCP.Tools.Reset)
    component(AgentWorkshop.MCP.Tools.Dismiss)
    component(AgentWorkshop.MCP.Tools.Cost)
    component(AgentWorkshop.MCP.Tools.AddWork)
    component(AgentWorkshop.MCP.Tools.Board)
    component(AgentWorkshop.MCP.Tools.ClaimWork)
    component(AgentWorkshop.MCP.Tools.CompleteWork)
    component(AgentWorkshop.MCP.Tools.FailWork)
    component(AgentWorkshop.MCP.Tools.FromProfile)

    @impl true
    def init(_client_info, frame) do
      {:ok, frame}
    end
  end

  # ── Router ──────────────────────────────────────────────────

  if Code.ensure_loaded?(Plug.Router) do
    defmodule AgentWorkshop.MCP.Router do
      @moduledoc false
      use Plug.Router

      alias AgentWorkshop.MCP, as: WorkshopMCP
      alias Anubis.Server.Transport.StreamableHTTP

      plug(:match)
      plug(:dispatch)

      match _ do
        if String.starts_with?(conn.request_path, "/mcp") do
          timeout = WorkshopMCP.request_timeout()

          opts =
            StreamableHTTP.Plug.init(
              server: AgentWorkshop.MCP.Server,
              request_timeout: timeout
            )

          StreamableHTTP.Plug.call(conn, opts)
        else
          send_resp(conn, 404, "not found")
        end
      end
    end
  end

  # ── Start Helper ────────────────────────────────────────────

  defmodule AgentWorkshop.MCP do
    @moduledoc """
    MCP server for Workshop. Exposes all Workshop functions as MCP tools.

    ## Quick start

        AgentWorkshop.MCP.start(port: 4222)

        # Then in .mcp.json:
        # {"mcpServers": {"workshop": {"type": "http", "url": "http://localhost:4222/mcp"}}}

    ## Available tools

    | Tool | Description |
    |---|---|
    | configure | Set global defaults (model, context) |
    | create_agent | Create a named agent with role and options |
    | ask | Send a message and wait for response |
    | cast | Send a message asynchronously |
    | await / await_all | Wait for async results |
    | status | Dashboard of all agents |
    | result | Get last response from an agent |
    | pipe | Chain output from one agent to another |
    | fan | Send same message to multiple agents |
    | info | Detailed agent info as JSON |
    | agents | List all agent names |
    | reset / dismiss | Agent lifecycle management |
    | cost | Show costs across all agents |
    """

    @default_request_timeout 300_000

    @doc false
    @spec request_timeout() :: pos_integer()
    def request_timeout do
      :persistent_term.get({__MODULE__, :request_timeout}, @default_request_timeout)
    end

    @doc """
    Start the Workshop MCP server over HTTP.

    ## Options

      * `:port` - HTTP port (default: 4222)
      * `:request_timeout` - MCP request timeout in ms (default: 300_000 / 5 min)
      * `:session_idle_timeout` - Session idle timeout in ms (default: 1_800_000 / 30 min)
    """
    @spec start(keyword()) :: Supervisor.on_start()
    def start(opts \\ []) do
      port = Keyword.get(opts, :port, 4222)
      request_timeout = Keyword.get(opts, :request_timeout, @default_request_timeout)
      session_idle_timeout = Keyword.get(opts, :session_idle_timeout, 1_800_000)

      unless Code.ensure_loaded?(Bandit) do
        raise "Bandit is required for HTTP transport. Add {:bandit, \"~> 1.0\"} to your deps."
      end

      :persistent_term.put({__MODULE__, :request_timeout}, request_timeout)
      :persistent_term.put({__MODULE__, :port}, port)

      children = [
        {AgentWorkshop.MCP.Server,
         transport: {:streamable_http, start: true},
         request_timeout: request_timeout,
         session_idle_timeout: session_idle_timeout},
        {Bandit, plug: AgentWorkshop.MCP.Router, port: port, scheme: :http}
      ]

      Supervisor.start_link(children,
        strategy: :one_for_one,
        name: AgentWorkshop.MCP.Supervisor
      )
    end
  end
end
