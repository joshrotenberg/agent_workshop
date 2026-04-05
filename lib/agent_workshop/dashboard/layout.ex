if Code.ensure_loaded?(Phoenix.Component) do
  defmodule AgentWorkshop.Dashboard.Layout do
    @moduledoc false
    use Phoenix.Component

    def root(assigns) do
      ~H"""
      <!DOCTYPE html>
      <html lang="en">
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
          <meta name="csrf-token" content={Phoenix.Controller.get_csrf_token()} />
          <title>Workshop Dashboard</title>
          <script src="https://cdn.jsdelivr.net/npm/phoenix@1.7.20/priv/static/phoenix.min.js"></script>
          <script src="https://cdn.jsdelivr.net/npm/phoenix_live_view@1.0.4/priv/static/phoenix_live_view.min.js"></script>
          <script>
            let liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket)
            liveSocket.connect()
          </script>
          <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, monospace; background: #0d1117; color: #c9d1d9; display: flex; min-height: 100vh; }
            nav { width: 220px; background: #161b22; border-right: 1px solid #30363d; padding: 1rem 0; flex-shrink: 0; }
            nav h1 { font-size: 1rem; padding: 0.5rem 1rem 1rem; color: #58a6ff; font-weight: 600; }
            nav a { display: block; padding: 0.6rem 1rem; color: #8b949e; text-decoration: none; font-size: 0.875rem; border-left: 3px solid transparent; }
            nav a:hover { color: #c9d1d9; background: #1c2128; }
            nav a.active { color: #58a6ff; border-left-color: #58a6ff; background: #1c2128; }
            main { flex: 1; padding: 1.5rem 2rem; overflow-y: auto; }
            h2 { font-size: 1.1rem; color: #e6edf3; margin-bottom: 1rem; font-weight: 600; }
            h3 { font-size: 0.9rem; color: #8b949e; margin: 1.5rem 0 0.5rem; text-transform: uppercase; letter-spacing: 0.05em; }
            table { width: 100%; border-collapse: collapse; margin-bottom: 1.5rem; }
            th { text-align: left; padding: 0.5rem 0.75rem; border-bottom: 1px solid #30363d; color: #8b949e; font-size: 0.75rem; text-transform: uppercase; font-weight: 500; }
            td { padding: 0.5rem 0.75rem; border-bottom: 1px solid #21262d; font-size: 0.875rem; }
            .badge { display: inline-block; padding: 0.15rem 0.5rem; border-radius: 10px; font-size: 0.75rem; font-weight: 500; }
            .badge-ready { background: #0d419d; color: #79c0ff; }
            .badge-claimed { background: #3d2e00; color: #e3b341; }
            .badge-in_progress { background: #3d2e00; color: #e3b341; }
            .badge-done { background: #0f3d1e; color: #56d364; }
            .badge-failed { background: #3d1418; color: #f85149; }
            .badge-blocked { background: #21262d; color: #8b949e; }
            .badge-new { background: #21262d; color: #8b949e; }
            .badge-cancelled { background: #21262d; color: #8b949e; }
            .badge-idle { background: #0f3d1e; color: #56d364; }
            .badge-working { background: #3d2e00; color: #e3b341; }
            .card { background: #161b22; border: 1px solid #30363d; border-radius: 6px; padding: 0.75rem; margin-bottom: 0.5rem; }
            .card-title { font-weight: 500; color: #e6edf3; }
            .card-meta { font-size: 0.75rem; color: #8b949e; margin-top: 0.25rem; }
            .columns { display: flex; gap: 1rem; }
            .column { flex: 1; min-width: 0; }
            .column-header { font-size: 0.8rem; color: #8b949e; padding: 0.4rem 0; border-bottom: 1px solid #30363d; margin-bottom: 0.5rem; text-transform: uppercase; font-weight: 500; }
            .stat { display: inline-block; background: #161b22; border: 1px solid #30363d; border-radius: 6px; padding: 0.75rem 1rem; margin: 0 0.5rem 0.5rem 0; }
            .stat-value { font-size: 1.2rem; font-weight: 600; color: #e6edf3; }
            .stat-label { font-size: 0.7rem; color: #8b949e; text-transform: uppercase; }
            .event { font-size: 0.8rem; padding: 0.3rem 0; border-bottom: 1px solid #21262d; }
            .event-time { color: #484f58; margin-right: 0.5rem; }
            .muted { color: #8b949e; }
            .mono { font-family: "SF Mono", "Fira Code", monospace; }
            .spec-text { font-size: 0.8rem; color: #8b949e; margin-top: 0.5rem; white-space: pre-wrap; max-height: 200px; overflow-y: auto; background: #0d1117; padding: 0.5rem; border-radius: 4px; }
            .cost { color: #56d364; }
          </style>
        </head>
        <body>
          <nav>
            <h1>Workshop</h1>
            <a href="/" class={if assigns[:active_tab] == :overview, do: "active"}>Overview</a>
            <a href="/board" class={if assigns[:active_tab] == :board, do: "active"}>Board</a>
            <a href="/workers" class={if assigns[:active_tab] == :workers, do: "active"}>Workers</a>
            <a href="/config" class={if assigns[:active_tab] == :config, do: "active"}>Config</a>
          </nav>
          <main>
            {@inner_content}
          </main>
        </body>
      </html>
      """
    end
  end
end
