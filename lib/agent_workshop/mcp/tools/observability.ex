if Code.ensure_loaded?(Anubis.Server) do
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
end
