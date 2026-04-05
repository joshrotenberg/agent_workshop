if Code.ensure_loaded?(Phoenix.Endpoint) do
  defmodule AgentWorkshop.Dashboard do
    @moduledoc """
    LiveView dashboard for real-time Workshop monitoring.

    Start the dashboard from IEx:

        dashboard(port: 4223)

    Or via configure:

        configure(dashboard: [port: 4223])

    Then visit http://localhost:4223 in your browser.

    Requires optional dependencies: phoenix, phoenix_live_view, phoenix_html.
    """

    alias AgentWorkshop.Dashboard.Endpoint

    @default_port 4223

    @doc """
    Start the dashboard on the given port.
    """
    @spec start(keyword()) :: {:ok, pid()} | {:error, term()}
    def start(opts \\ []) do
      port = Keyword.get(opts, :port, @default_port)

      config = [
        http: [port: port],
        server: true,
        secret_key_base: generate_secret(),
        live_view: [signing_salt: "workshop_lv"],
        url: [host: "localhost"],
        adapter: Bandit.PhoenixAdapter
      ]

      Application.put_env(:agent_workshop, Endpoint, config, persistent: true)

      case Endpoint.start_link([]) do
        {:ok, pid} ->
          IO.puts(
            IO.ANSI.cyan() <>
              "Dashboard running at http://localhost:#{port}" <>
              IO.ANSI.reset()
          )

          {:ok, pid}

        {:error, {:already_started, pid}} ->
          IO.puts(
            IO.ANSI.yellow() <>
              "Dashboard already running at http://localhost:#{port}" <>
              IO.ANSI.reset()
          )

          {:ok, pid}

        error ->
          error
      end
    end

    defp generate_secret do
      :crypto.strong_rand_bytes(64) |> Base.encode64() |> binary_part(0, 64)
    end
  end
end
