defmodule AgentWorkshop.PubSub do
  @moduledoc """
  Event bus for agent coordination.

  Agents and processes subscribe to topics and receive messages when
  events occur. Workshop auto-publishes lifecycle events; you can
  also publish custom events.

  ## Auto-published events

      {:agent, :ask_complete, agent_name, result}
      {:agent, :cast_complete, agent_name, result}
      {:agent, :error, agent_name, reason}
      {:agent, :created, agent_name}
      {:agent, :dismissed, agent_name}
      {:agent, :reset, agent_name}
      {:store, :put, key}
      {:store, :delete, key}
      {:store, :clear}

  ## Usage from IEx

      # Subscribe the current process
      AgentWorkshop.PubSub.subscribe(:agent_events)

      # Publish a custom event
      AgentWorkshop.PubSub.broadcast(:deploy_ready, %{sha: "abc123"})

      # Receive (in IEx or a GenServer)
      receive do
        {:workshop_event, topic, event} -> IO.inspect(event)
      end

  ## Usage in agents

  Agents don't subscribe directly (they're CLI subprocesses). Instead,
  use periodic tasks (#9) or the work board (#16) for reactive patterns.
  PubSub is primarily for BEAM processes: LiveView dashboards, custom
  GenServers, telemetry handlers.
  """

  @registry AgentWorkshop.PubSub.Registry

  @doc """
  Subscribe the calling process to a topic.

  The process will receive `{:workshop_event, topic, event}` messages.
  """
  @spec subscribe(term()) :: :ok
  def subscribe(topic) do
    ensure_registry!()
    Registry.register(@registry, topic, [])
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc """
  Unsubscribe the calling process from a topic.
  """
  @spec unsubscribe(term()) :: :ok
  def unsubscribe(topic) do
    ensure_registry!()
    Registry.unregister(@registry, topic)
    :ok
  end

  @doc """
  Broadcast an event to all subscribers of the `:all` topic
  and to subscribers of the event's specific topic.

  Events are tuples like `{:agent, :ask_complete, name, result}`.
  The first element is used as the specific topic.
  """
  @spec broadcast(term()) :: :ok
  def broadcast(event) when is_tuple(event) do
    topic = elem(event, 0)
    do_broadcast(topic, event)
    do_broadcast(:all, event)
    :ok
  end

  @doc """
  Broadcast an event to a specific topic.
  """
  @spec broadcast(term(), term()) :: :ok
  def broadcast(topic, event) do
    do_broadcast(topic, event)
    do_broadcast(:all, {:custom, topic, event})
    :ok
  end

  @doc false
  def registry_name, do: @registry

  @doc false
  def start_registry do
    case Registry.start_link(keys: :duplicate, name: @registry) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end

  defp do_broadcast(topic, event) do
    if Process.whereis(@registry) do
      Registry.dispatch(@registry, topic, &dispatch_to_subscribers(&1, topic, event))
    end
  end

  defp dispatch_to_subscribers(entries, topic, event) do
    for {pid, _value} <- entries do
      send(pid, {:workshop_event, topic, event})
    end
  end

  defp ensure_registry! do
    unless Process.whereis(@registry) do
      raise "Workshop not started. Call configure/1 first."
    end
  end
end
