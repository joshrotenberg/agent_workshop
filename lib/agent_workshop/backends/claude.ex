defmodule AgentWorkshop.Backends.Claude do
  @moduledoc """
  Claude Code CLI backend for AgentWorkshop.

  Requires the `claude_wrapper` package:

      {:claude_wrapper, "~> 0.5"}

  ## Usage

      configure(
        backend: AgentWorkshop.Backends.Claude,
        backend_config: ClaudeWrapper.Config.new(working_dir: "."),
        model: "sonnet"
      )
  """

  @behaviour AgentWorkshop.Backend

  @impl true
  def start_session(config, opts) do
    ensure_claude_wrapper!()

    apply(ClaudeWrapper.SessionServer, :start_link, [
      [config: config, query_opts: opts]
    ])
  end

  @impl true
  def send_message(server, prompt, opts) do
    case apply(ClaudeWrapper.SessionServer, :send_message, [server, prompt, opts]) do
      {:ok, result} -> {:ok, normalize_result(result)}
      {:error, _} = err -> err
    end
  end

  @impl true
  def session_id(server) do
    apply(ClaudeWrapper.SessionServer, :session_id, [server])
  end

  @impl true
  def history(server) do
    apply(ClaudeWrapper.SessionServer, :history, [server])
    |> Enum.map(&normalize_result/1)
  end

  @impl true
  def total_cost(server) do
    apply(ClaudeWrapper.SessionServer, :total_cost, [server])
  end

  @impl true
  def turn_count(server) do
    apply(ClaudeWrapper.SessionServer, :turn_count, [server])
  end

  @impl true
  def last_result(server) do
    case apply(ClaudeWrapper.SessionServer, :last_result, [server]) do
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

  # Convert ClaudeWrapper.Result struct to the Backend result map
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

  defp ensure_claude_wrapper! do
    unless Code.ensure_loaded?(ClaudeWrapper.SessionServer) do
      raise """
      ClaudeWrapper is required for the Claude backend.
      Add {:claude_wrapper, "~> 0.5"} to your deps.
      """
    end
  end
end
