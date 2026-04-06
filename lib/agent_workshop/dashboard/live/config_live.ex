if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule AgentWorkshop.Dashboard.Live.ConfigLive do
    @moduledoc false
    use Phoenix.LiveView

    import AgentWorkshop.Dashboard.Live.Components

    alias AgentWorkshop.{Budget, Persistence, Profiles, Store}

    @impl true
    def mount(_params, _session, socket) do
      if connected?(socket) do
        AgentWorkshop.PubSub.subscribe(:store)
      end

      {:ok, assign(socket, active_tab: :config) |> refresh_data()}
    end

    @impl true
    def handle_info({:workshop_event, _, _}, socket) do
      {:noreply, refresh_data(socket)}
    end

    def handle_info(_, socket), do: {:noreply, socket}

    defp refresh_data(socket) do
      assign(socket,
        backend: safe_get_config(:backend),
        context: safe_get_config(:context),
        persistence_enabled: safe_persistence(),
        store_entries: safe_store(),
        profiles: safe_profiles(),
        budget: safe_budget()
      )
    end

    defp safe_get_config(key) do
      :persistent_term.get({AgentWorkshop, key}, nil)
    rescue
      _ -> nil
    end

    defp safe_persistence do
      Persistence.enabled?()
    rescue
      _ -> false
    end

    defp safe_store do
      Store.entries()
    rescue
      _ -> []
    end

    defp safe_profiles do
      Profiles.list()
      |> Enum.map(&{&1, Profiles.get(&1)})
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
    rescue
      _ -> []
    end

    defp safe_budget do
      Budget.info(:global)
    rescue
      _ -> %{limit: nil, spent: 0.0, remaining: nil}
    end

    @impl true
    def render(assigns) do
      ~H"""
      <h2>Configuration</h2>

      <h3>Backend</h3>
      <div class="card">
        <div class="card-title">{if @backend, do: inspect(@backend), else: "Not configured"}</div>
        <%= if @context do %>
          <div class="card-meta muted" style="margin-top: 0.5rem;">Context: {String.slice(@context, 0..200)}</div>
        <% end %>
      </div>

      <h3>Budget</h3>
      <div class="card">
        <%= if @budget.limit do %>
          <div class="card-title cost">{format_cost(@budget.spent)} / {format_cost(@budget.limit)}</div>
          <div class="card-meta muted">{format_cost(@budget.remaining || 0)} remaining</div>
        <% else %>
          <div class="card-title">No budget set</div>
          <div class="card-meta muted">Spent: {format_cost(@budget.spent)}</div>
        <% end %>
      </div>

      <h3>Persistence</h3>
      <div class="card">
        <div class="card-title">{if @persistence_enabled, do: "Enabled", else: "Disabled"}</div>
      </div>

      <h3>Profiles</h3>
      <%= if @profiles == [] do %>
        <p class="muted">No profiles defined.</p>
      <% else %>
        <table>
          <thead>
            <tr><th>Name</th><th>Role</th><th>Options</th></tr>
          </thead>
          <tbody>
            <%= for {name, %{role: role, opts: opts}} <- @profiles do %>
              <tr>
                <td class="mono">{inspect(name)}</td>
                <td>{role || "(no role)"}</td>
                <td class="muted">{inspect(opts, limit: 5)}</td>
              </tr>
            <% end %>
          </tbody>
        </table>
      <% end %>

      <h3>Store</h3>
      <%= if @store_entries == [] do %>
        <p class="muted">Store is empty.</p>
      <% else %>
        <table>
          <thead>
            <tr><th>Key</th><th>Value</th></tr>
          </thead>
          <tbody>
            <%= for {key, value} <- @store_entries do %>
              <tr>
                <td class="mono">{inspect(key)}</td>
                <td>{inspect(value, limit: 80, printable_limit: 200)}</td>
              </tr>
            <% end %>
          </tbody>
        </table>
      <% end %>
      """
    end
  end
end
