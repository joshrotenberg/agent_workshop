if Code.ensure_loaded?(Phoenix.Router) do
  defmodule AgentWorkshop.Dashboard.Router do
    @moduledoc false
    use Phoenix.Router
    import Phoenix.LiveView.Router

    pipeline :browser do
      plug(:accepts, ["html"])
      plug(:fetch_session)
      plug(:put_root_layout, html: {AgentWorkshop.Dashboard.Layout, :root})
      plug(:protect_from_forgery)
      plug(:put_secure_browser_headers)
    end

    scope "/", AgentWorkshop.Dashboard.Live do
      pipe_through(:browser)

      live("/", OverviewLive)
      live("/board", BoardLive)
      live("/workers", WorkersLive)
      live("/config", ConfigLive)
      live("/reference", ReferenceLive)
    end
  end
end
