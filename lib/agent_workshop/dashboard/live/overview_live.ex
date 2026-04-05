if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule AgentWorkshop.Dashboard.Live.OverviewLive do
    @moduledoc false
    use Phoenix.LiveView

    import AgentWorkshop.Dashboard.Live.Components

    alias AgentWorkshop.{Work, Workshop}

    @impl true
    def mount(_params, _session, socket) do
      if connected?(socket) do
        AgentWorkshop.PubSub.subscribe(:all)
      end

      {:ok, assign(socket, active_tab: :overview) |> refresh_data()}
    end

    @impl true
    def handle_info({:workshop_event, _, _}, socket) do
      {:noreply, refresh_data(socket)}
    end

    def handle_info(_, socket), do: {:noreply, socket}

    defp refresh_data(socket) do
      assign(socket,
        agents: safe_status(),
        summary: Work.summary(),
        total_cost: safe_total_cost(),
        events: safe_events()
      )
    end

    defp safe_status do
      :ets.tab2list(:agent_workshop_agents)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {name, e} ->
        %{
          name: name,
          status: e.status,
          task: e.task_text,
          cost: e.cumulative_cost,
          turns: e.turn_count,
          role: e.role
        }
      end)
    rescue
      _ -> []
    end

    defp safe_total_cost do
      Workshop.total_cost()
    rescue
      _ -> 0.0
    end

    defp safe_events do
      AgentWorkshop.EventLog.recent(last: 15)
      |> Enum.filter(& &1.formatted)
    rescue
      _ -> []
    end

    @impl true
    def render(assigns) do
      ~H"""
      <h2>Overview</h2>

      <div>
        <div class="stat">
          <div class="stat-value">{length(@agents)}</div>
          <div class="stat-label">Agents</div>
        </div>
        <div class="stat">
          <div class="stat-value cost">{format_cost(@total_cost)}</div>
          <div class="stat-label">Total Cost</div>
        </div>
        <%= for {status, count} <- @summary do %>
          <div class="stat">
            <div class="stat-value">{count}</div>
            <div class="stat-label">{status}</div>
          </div>
        <% end %>
      </div>

      <h3>Agents</h3>
      <%= if @agents == [] do %>
        <p class="muted">No agents running.</p>
      <% else %>
        <table>
          <thead>
            <tr>
              <th>Agent</th>
              <th>Status</th>
              <th>Task</th>
              <th>Cost</th>
              <th>Turns</th>
            </tr>
          </thead>
          <tbody>
            <%= for agent <- @agents do %>
              <tr>
                <td class="mono">{inspect(agent.name)}</td>
                <td><.status_badge status={agent.status} /></td>
                <td>{truncate_text(agent.task, 50)}</td>
                <td class="cost">{format_cost(agent.cost)}</td>
                <td>{agent.turns}</td>
              </tr>
            <% end %>
          </tbody>
        </table>
      <% end %>

      <h3>Recent Events</h3>
      <%= if @events == [] do %>
        <p class="muted">No events recorded.</p>
      <% else %>
        <%= for event <- Enum.reverse(@events) do %>
          <div class="event">
            <span class="event-time">{Calendar.strftime(event.timestamp, "%H:%M:%S")}</span>
            {event.formatted}
          </div>
        <% end %>
      <% end %>
      """
    end

    defp truncate_text(nil, _), do: ""
    defp truncate_text(str, max) when byte_size(str) <= max, do: str
    defp truncate_text(str, max), do: String.slice(str, 0, max - 3) <> "..."
  end
end
