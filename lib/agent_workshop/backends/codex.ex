defmodule AgentWorkshop.Backends.Codex do
  @moduledoc """
  OpenAI Codex CLI backend for AgentWorkshop.

  Requires the `codex_wrapper` package:

      {:codex_wrapper, "~> 0.1"}

  ## Usage

      configure(
        backend: AgentWorkshop.Backends.Codex,
        backend_config: CodexWrapper.Config.new(working_dir: "."),
        model: "o3"
      )
  """

  @behaviour AgentWorkshop.Backend

  @impl true
  def start_session(config, opts) do
    ensure_codex_wrapper!()

    apply(CodexWrapper.SessionServer, :start_link, [
      [config: config, exec_opts: opts]
    ])
  end

  @impl true
  def send_message(server, prompt, opts) do
    case apply(CodexWrapper.SessionServer, :send_message, [server, prompt, opts]) do
      {:ok, result} -> {:ok, normalize_result(result)}
      {:error, _} = err -> err
    end
  end

  @impl true
  def session_id(server) do
    apply(CodexWrapper.SessionServer, :session_id, [server])
  end

  @impl true
  def history(server) do
    apply(CodexWrapper.SessionServer, :history, [server])
    |> Enum.map(&normalize_result/1)
  end

  @impl true
  def total_cost(server) do
    apply(CodexWrapper.SessionServer, :total_cost, [server])
  end

  @impl true
  def turn_count(server) do
    apply(CodexWrapper.SessionServer, :turn_count, [server])
  end

  @impl true
  def last_result(server) do
    case apply(CodexWrapper.SessionServer, :last_result, [server]) do
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
    unless Code.ensure_loaded?(CodexWrapper.SessionServer) do
      raise """
      CodexWrapper is required for the Codex backend.
      Add {:codex_wrapper, "~> 0.1"} to your deps.
      """
    end
  end
end
