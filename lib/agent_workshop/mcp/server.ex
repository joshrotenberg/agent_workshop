if Code.ensure_loaded?(Anubis.Server) do
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
end
