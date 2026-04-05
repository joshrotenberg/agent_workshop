if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule AgentWorkshop.Dashboard.Live.BoardLive do
    @moduledoc false
    use Phoenix.LiveView

    import AgentWorkshop.Dashboard.Live.Components

    alias AgentWorkshop.Work

    @columns [:ready, :claimed, :in_progress, :done, :failed]
    @refresh_interval 5_000

    @impl true
    def mount(_params, _session, socket) do
      if connected?(socket) do
        AgentWorkshop.PubSub.subscribe(:work)
        Process.send_after(self(), :tick, @refresh_interval)
      end

      {:ok, assign(socket, active_tab: :board, expanded: nil) |> refresh_data()}
    end

    @impl true
    def handle_info({:workshop_event, :work, _}, socket) do
      {:noreply, refresh_data(socket)}
    end

    def handle_info(:tick, socket) do
      Process.send_after(self(), :tick, @refresh_interval)
      {:noreply, refresh_data(socket)}
    end

    def handle_info(_, socket), do: {:noreply, socket}

    @impl true
    def handle_event("toggle", %{"id" => id}, socket) do
      id = String.to_existing_atom(id)
      expanded = if socket.assigns.expanded == id, do: nil, else: id
      {:noreply, assign(socket, expanded: expanded)}
    end

    defp refresh_data(socket) do
      items = safe_list()

      grouped =
        Enum.reduce(@columns, %{}, fn col, acc ->
          Map.put(acc, col, Enum.filter(items, &(&1.status == col)))
        end)

      # Catch remaining statuses (new, blocked, cancelled)
      other =
        items
        |> Enum.reject(&(&1.status in @columns))

      assign(socket, items: items, grouped: grouped, other: other)
    end

    defp safe_list do
      Work.list()
    rescue
      _ -> []
    end

    @impl true
    def render(assigns) do
      ~H"""
      <h2>Work Board</h2>

      <%= if @items == [] do %>
        <p class="muted">Board is empty. Use work/3 to add items.</p>
      <% else %>
        <div class="columns">
          <%= for col <- [:ready, :claimed, :in_progress, :done, :failed] do %>
            <div class="column">
              <div class="column-header">{col} ({length(@grouped[col])})</div>
              <%= for item <- @grouped[col] do %>
                <div class="card" phx-click="toggle" phx-value-id={item.id}>
                  <div class="card-title">{inspect(item.id)}</div>
                  <div class="card-meta">
                    <span class="badge badge-{item.type}">{item.type}</span>
                    <%= if item.claimed_by do %>
                      <span class="muted"> {item.claimed_by}</span>
                    <% end %>
                    <%= if item.status == :in_progress and item.started_at do %>
                      <span class="muted"> {format_elapsed(item.started_at, :now)}</span>
                    <% end %>
                    <%= if item.status == :done and item.started_at && item.completed_at do %>
                      <span class="muted"> took {format_elapsed(item.started_at, item.completed_at)}</span>
                    <% end %>
                  </div>
                  <div class="card-meta muted">{item.title}</div>
                  <%= if @expanded == item.id do %>
                    <%= if item.spec do %>
                      <div class="spec-text">{item.spec}</div>
                    <% end %>
                    <%= if item.result do %>
                      <div class="spec-text">{String.slice(item.result, 0..2000)}</div>
                    <% end %>
                    <%= if item.error do %>
                      <div class="spec-text" style="color: #f85149;">{item.error}</div>
                    <% end %>
                    <%= if item.depends_on != [] do %>
                      <div class="card-meta">deps: {inspect(item.depends_on)}</div>
                    <% end %>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

        <%= if @other != [] do %>
          <h3>Other ({length(@other)})</h3>
          <%= for item <- @other do %>
            <div class="card">
              <div class="card-title">{inspect(item.id)} <.status_badge status={item.status} /></div>
              <div class="card-meta muted">{item.title}</div>
              <%= if item.depends_on != [] do %>
                <div class="card-meta">deps: {inspect(item.depends_on)}</div>
              <% end %>
            </div>
          <% end %>
        <% end %>
      <% end %>
      """
    end
  end
end
