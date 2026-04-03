if Code.ensure_loaded?(Anubis.Server) do
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

    require Logger

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
      * `:debug` - when `true`, skip suppression of Anubis transport debug logs (default: false)
    """
    @spec start(keyword()) :: Supervisor.on_start()
    def start(opts \\ []) do
      port = Keyword.get(opts, :port, 4222)
      request_timeout = Keyword.get(opts, :request_timeout, @default_request_timeout)
      session_idle_timeout = Keyword.get(opts, :session_idle_timeout, 1_800_000)
      debug = Keyword.get(opts, :debug, false)

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

      result =
        Supervisor.start_link(children,
          strategy: :one_for_one,
          name: AgentWorkshop.MCP.Supervisor
        )

      unless debug do
        Logger.put_module_level(Anubis.Server.Transport.StreamableHTTP, :warning)
        Logger.put_module_level(Anubis.Server.Transport.StreamableHTTP.Plug, :warning)
        Logger.put_module_level(Anubis.Server.Session, :warning)
        Logger.put_module_level(Anubis.Server.Transport.STDIO, :warning)
      end

      result
    end
  end
end
