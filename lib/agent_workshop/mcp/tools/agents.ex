if Code.ensure_loaded?(Anubis.Server) do
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
end
