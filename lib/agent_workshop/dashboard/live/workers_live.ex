if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule AgentWorkshop.Dashboard.Live.WorkersLive do
    @moduledoc false
    use Phoenix.LiveView

    import AgentWorkshop.Dashboard.Live.Components

    @impl true
    def mount(_params, _session, socket) do
      if connected?(socket) do
        AgentWorkshop.PubSub.subscribe(:work)
        AgentWorkshop.PubSub.subscribe(:schedule)
      end

      {:ok, assign(socket, active_tab: :workers) |> refresh_data()}
    end

    @impl true
    def handle_info({:workshop_event, _, _}, socket) do
      {:noreply, refresh_data(socket)}
    end

    def handle_info(_, socket), do: {:noreply, socket}

    defp refresh_data(socket) do
      assign(socket,
        workers: safe_workers(),
        schedules: safe_schedules()
      )
    end

    defp safe_workers do
      AgentWorkshop.BoardWorker.list_all()
      |> Enum.map(&AgentWorkshop.BoardWorker.get_info/1)
      |> Enum.reject(&is_nil/1)
    rescue
      _ -> []
    end

    defp safe_schedules do
      AgentWorkshop.Scheduler.list_all()
      |> Enum.map(&AgentWorkshop.Scheduler.get_info/1)
      |> Enum.reject(&is_nil/1)
    rescue
      _ -> []
    end

    @impl true
    def render(assigns) do
      ~H"""
      <h2>Workers</h2>

      <h3>Board Workers</h3>
      <%= if @workers == [] do %>
        <p class="muted">No board workers running.</p>
      <% else %>
        <table>
          <thead>
            <tr>
              <th>Agent</th>
              <th>Type</th>
              <th>Interval</th>
              <th>Completed</th>
              <th>Current</th>
              <th>Worktree</th>
            </tr>
          </thead>
          <tbody>
            <%= for w <- @workers do %>
              <tr>
                <td class="mono">{inspect(w.agent_name)}</td>
                <td><span class="badge badge-ready">{w.work_type}</span></td>
                <td>{format_interval(w.interval)}</td>
                <td>{w.claims_completed}</td>
                <td>
                  <%= if w.current_item do %>
                    <span class="mono">{inspect(w.current_item)}</span>
                  <% else %>
                    <span class="muted">idle</span>
                  <% end %>
                </td>
                <td>{if w.worktree, do: "yes", else: "no"}</td>
              </tr>
            <% end %>
          </tbody>
        </table>
      <% end %>

      <h3>Schedules</h3>
      <%= if @schedules == [] do %>
        <p class="muted">No active schedules.</p>
      <% else %>
        <table>
          <thead>
            <tr>
              <th>Agent</th>
              <th>Interval</th>
              <th>Runs</th>
              <th>Last Run</th>
            </tr>
          </thead>
          <tbody>
            <%= for s <- @schedules do %>
              <tr>
                <td class="mono">{inspect(s.agent)}</td>
                <td>{format_interval(s.interval)}</td>
                <td>{s.run_count}</td>
                <td>
                  <%= if s.last_run_at do %>
                    {Calendar.strftime(s.last_run_at, "%H:%M:%S")}
                  <% else %>
                    <span class="muted">never</span>
                  <% end %>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      <% end %>
      """
    end
  end
end
