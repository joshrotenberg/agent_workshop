if Code.ensure_loaded?(Phoenix.Endpoint) do
  defmodule AgentWorkshop.Dashboard.Endpoint do
    @moduledoc false
    use Phoenix.Endpoint, otp_app: :agent_workshop

    socket("/live", Phoenix.LiveView.Socket,
      websocket: [connect_info: [:peer_data]],
      longpoll: false
    )

    plug(Plug.Parsers,
      parsers: [:urlencoded],
      pass: ["text/html"]
    )

    plug(Plug.MethodOverride)
    plug(Plug.Head)
    plug(Plug.Session, store: :cookie, key: "_workshop", signing_salt: "workshop_dash")

    plug(AgentWorkshop.Dashboard.Router)
  end
end
