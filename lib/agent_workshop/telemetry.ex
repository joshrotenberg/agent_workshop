defmodule AgentWorkshop.Telemetry do
  @moduledoc """
  Telemetry events for Workshop operations.

  All events use the `[:agent_workshop, ...]` prefix. Attach handlers
  for logging, metrics, cost tracking, or triggering workflows.

  ## Events

      [:agent_workshop, :ask, :start]
        measurements: %{system_time: integer}
        metadata: %{agent: atom, prompt: String.t()}

      [:agent_workshop, :ask, :stop]
        measurements: %{duration: integer, cost: float}
        metadata: %{agent: atom, prompt: String.t()}

      [:agent_workshop, :ask, :error]
        measurements: %{duration: integer}
        metadata: %{agent: atom, prompt: String.t(), error: term}

      [:agent_workshop, :cast, :start]
        measurements: %{system_time: integer}
        metadata: %{agent: atom, prompt: String.t()}

      [:agent_workshop, :cast, :complete]
        measurements: %{duration: integer, cost: float}
        metadata: %{agent: atom}

      [:agent_workshop, :agent, :created]
        measurements: %{system_time: integer}
        metadata: %{agent: atom, role: String.t() | nil, backend: module}

      [:agent_workshop, :agent, :dismissed]
        measurements: %{system_time: integer}
        metadata: %{agent: atom}

  ## Example handler

      :telemetry.attach("cost-logger", [:agent_workshop, :ask, :stop], fn
        _event, %{cost: cost}, %{agent: agent}, _config ->
          IO.puts("Agent \#{agent} cost $\#{cost}")
      end, nil)
  """

  @doc """
  Emit a telemetry start event. Returns the start time for computing duration.
  """
  @spec start(atom(), map()) :: integer()
  def start(action, metadata \\ %{}) do
    start_time = System.monotonic_time()

    :telemetry.execute(
      [:agent_workshop, action, :start],
      %{system_time: System.system_time()},
      metadata
    )

    start_time
  end

  @doc """
  Emit a telemetry stop event with duration.
  """
  @spec stop(atom(), integer(), map(), map()) :: :ok
  def stop(action, start_time, measurements \\ %{}, metadata \\ %{}) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:agent_workshop, action, :stop],
      Map.merge(%{duration: duration}, measurements),
      metadata
    )
  end

  @doc """
  Emit a telemetry error event.
  """
  @spec error(atom(), integer(), term(), map()) :: :ok
  def error(action, start_time, error, metadata \\ %{}) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:agent_workshop, action, :error],
      %{duration: duration},
      Map.put(metadata, :error, error)
    )
  end

  @doc """
  Emit a one-shot telemetry event (no start/stop pair).
  """
  @spec event(atom(), map(), map()) :: :ok
  def event(action, measurements \\ %{}, metadata \\ %{}) do
    :telemetry.execute(
      [:agent_workshop, action],
      Map.merge(%{system_time: System.system_time()}, measurements),
      metadata
    )
  end
end
