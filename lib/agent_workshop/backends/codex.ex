defmodule AgentWorkshop.Backends.Codex do
  @moduledoc """
  OpenAI Codex CLI backend for AgentWorkshop.

  Requires the `codex_wrapper` package:

      {:codex_wrapper, "~> 0.2"}

  ## Usage

      configure(
        backend: AgentWorkshop.Backends.Codex,
        backend_config: CodexWrapper.Config.new(working_dir: "."),
        model: "o3"
      )
  """

  @behaviour AgentWorkshop.Backend

  # Use module attribute to avoid compile-time "module not available" warnings
  # when codex_wrapper is not a dependency of the consuming project.
  @session_server CodexWrapper.SessionServer

  @impl true
  def start_session(config, opts) do
    ensure_codex_wrapper!()
    @session_server.start_link(config: config, exec_opts: opts)
  end

  @impl true
  def send_message(server, prompt, opts) do
    case @session_server.send_message(server, prompt, opts) do
      {:ok, result} -> {:ok, normalize_result(result)}
      {:error, _} = err -> err
    end
  end

  @impl true
  def session_id(server), do: @session_server.session_id(server)

  @impl true
  def history(server) do
    server |> @session_server.history() |> Enum.map(&normalize_result/1)
  end

  @impl true
  def total_cost(server), do: @session_server.total_cost(server)

  @impl true
  def turn_count(server), do: @session_server.turn_count(server)

  @impl true
  def last_result(server) do
    case @session_server.last_result(server) do
      nil -> nil
      result -> normalize_result(result)
    end
  end

  @impl true
  def stop_session(server) do
    GenServer.stop(server, :normal)
    :ok
  catch
    :exit, _ -> :ok
  end

  defp normalize_result(result) do
    %{
      result: Map.get(result, :result, ""),
      session_id: Map.get(result, :session_id),
      cost_usd: Map.get(result, :cost_usd),
      is_error: Map.get(result, :is_error, false),
      duration_ms: Map.get(result, :duration_ms),
      num_turns: Map.get(result, :num_turns)
    }
  end

  defp ensure_codex_wrapper! do
    unless Code.ensure_loaded?(@session_server) do
      raise "CodexWrapper is required. Add {:codex_wrapper, \"~> 0.2\"} to your deps."
    end
  end
end
