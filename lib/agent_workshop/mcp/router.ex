if Code.ensure_loaded?(Anubis.Server) do
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
          conn
          |> fix_stale_session_response()
          |> dispatch_to_mcp()
        else
          send_resp(conn, 404, "not found")
        end
      end

      # Workaround for Anubis issues #53 and #89:
      # When a session expires, Anubis returns HTTP 200 with a JSON-RPC
      # "Server not initialized" error instead of HTTP 404. The MCP spec
      # requires 404 so clients know to reinitialize. Convert it.
      defp fix_stale_session_response(conn) do
        Plug.Conn.register_before_send(conn, fn conn ->
          if conn.status == 200 and is_binary(conn.resp_body) and
               String.contains?(conn.resp_body, "Server not initialized") do
            %{conn | status: 404}
          else
            conn
          end
        end)
      end

      defp dispatch_to_mcp(conn) do
        timeout = WorkshopMCP.request_timeout()

        opts =
          StreamableHTTP.Plug.init(
            server: AgentWorkshop.MCP.Server,
            request_timeout: timeout
          )

        StreamableHTTP.Plug.call(conn, opts)
      end
    end
  end
end
