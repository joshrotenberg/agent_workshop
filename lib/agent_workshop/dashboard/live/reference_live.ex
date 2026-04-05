if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule AgentWorkshop.Dashboard.Live.ReferenceLive do
    @moduledoc false
    use Phoenix.LiveView

    @impl true
    def mount(_params, _session, socket) do
      {:ok, assign(socket, active_tab: :reference)}
    end

    @impl true
    def render(assigns) do
      ~H"""
      <h2>Command Reference</h2>
      <p class="muted" style="margin-bottom: 1.5rem;">All commands available after <code>import AgentWorkshop.Workshop</code> in IEx.</p>

      <h3>Configuration</h3>
      <table>
        <thead><tr><th>Command</th><th>Description</th></tr></thead>
        <tbody>
          <.cmd name="configure(opts)" desc="Set global defaults: backend, model, context, persistence, dashboard" />
          <.cmd name="load(path)" desc="Load a setup file (default .workshop.exs)" />
          <.cmd name="stop()" desc="Dismiss all agents, clear state. Supervision tree stays running" />
          <.cmd name="mcp_server(opts)" desc="Start the MCP server (default port 4222)" />
          <.cmd name="dashboard(opts)" desc="Start the LiveView dashboard (default port 4223)" />
        </tbody>
      </table>

      <h3>Agents</h3>
      <table>
        <thead><tr><th>Command</th><th>Description</th></tr></thead>
        <tbody>
          <.cmd name="agent(name, role, opts)" desc="Create a named agent with a role and options" />
          <.cmd name="dismiss(name)" desc="Remove an agent and stop its session" />
          <.cmd name="reset(name)" desc="Clear conversation history, keep agent config" />
          <.cmd name="reset_all()" desc="Dismiss all agents and reset global config" />
          <.cmd name="agents()" desc="List all agent names" />
          <.cmd name="info(name)" desc="Detailed agent info map (status, cost, turns, model)" />
          <.cmd name="status()" desc="Agent dashboard table. Returns list of maps" />
        </tbody>
      </table>

      <h3>Interaction</h3>
      <table>
        <thead><tr><th>Command</th><th>Description</th></tr></thead>
        <tbody>
          <.cmd name="ask(name, prompt)" desc="Send message, wait for response. Returns agent name for piping" />
          <.cmd name="cast(name, prompt)" desc="Send message async, returns :ok immediately" />
          <.cmd name="await(name)" desc="Wait for a cast to complete" />
          <.cmd name="await_all()" desc="Wait for all pending casts" />
          <.cmd name="pipe(from, to, message)" desc="Send from's result to to with message context" />
          <.cmd name="fan(message, agents)" desc="Send same message to multiple agents in parallel" />
          <.cmd name="result(name)" desc="Get last response text. Pass :full for complete map" />
          <.cmd name="history(name, opts)" desc="Print conversation turns. Use last: N to limit" />
        </tbody>
      </table>

      <h3>Cost</h3>
      <table>
        <thead><tr><th>Command</th><th>Description</th></tr></thead>
        <tbody>
          <.cmd name="cost()" desc="Show all agent costs and total" />
          <.cmd name="cost(name)" desc="Show cost for one agent" />
          <.cmd name="total_cost()" desc="Total cost across all agents (float)" />
          <.cmd name="budget()" desc="Show global budget info" />
          <.cmd name="budget(name)" desc="Show per-agent budget" />
          <.cmd name="reset_budget()" desc="Clear all budget limits" />
        </tbody>
      </table>

      <h3>Work Board</h3>
      <table>
        <thead><tr><th>Command</th><th>Description</th></tr></thead>
        <tbody>
          <.cmd name="work(id, title, opts)" desc="Add a work item. Opts: type, spec, priority, depends_on" />
          <.cmd name="board(filters)" desc="Show board. Filter by status: or type:. Returns items" />
          <.cmd name="work_item(id)" desc="Get a single work item struct" />
          <.cmd name="claim_work(id, agent)" desc="Agent claims a ready work item" />
          <.cmd name="start_work(id)" desc="Mark claimed item as in_progress" />
          <.cmd name="complete_work(id, result)" desc="Mark done, unblocks dependents" />
          <.cmd name="fail_work(id, error)" desc="Mark failed, blocks dependents" />
          <.cmd name="cancel_work(id)" desc="Cancel a work item" />
          <.cmd name="work_from_result(agent, id, opts)" desc="Create work item with agent's result as spec" />
        </tbody>
      </table>

      <h3>Board Workers</h3>
      <table>
        <thead><tr><th>Command</th><th>Description</th></tr></thead>
        <tbody>
          <.cmd name="board_worker(name, type, opts)" desc="Start a worker that polls board for type. Needs profile:" />
          <.cmd name="workers()" desc="List active board workers and their status" />
        </tbody>
      </table>

      <h3>Scheduling</h3>
      <table>
        <thead><tr><th>Command</th><th>Description</th></tr></thead>
        <tbody>
          <.cmd name="every(name, prompt, opts)" desc="Run agent prompt on interval. Opts: interval (ms)" />
          <.cmd name="schedules()" desc="List active schedules" />
          <.cmd name="cancel(name)" desc="Stop a recurring schedule" />
        </tbody>
      </table>

      <h3>Profiles</h3>
      <table>
        <thead><tr><th>Command</th><th>Description</th></tr></thead>
        <tbody>
          <.cmd name="profile(name, role, opts)" desc="Define a reusable agent template" />
          <.cmd name="from_profile(profile, agent, overrides)" desc="Create agent from profile with optional overrides" />
          <.cmd name="profiles()" desc="List defined profiles" />
        </tbody>
      </table>

      <h3>Shared Store</h3>
      <table>
        <thead><tr><th>Command</th><th>Description</th></tr></thead>
        <tbody>
          <.cmd name="put(key, value)" desc="Store a value. Keys can be atoms, strings, or tuples" />
          <.cmd name="get(key)" desc="Retrieve a value (nil if missing)" />
          <.cmd name="store()" desc="Show all store entries" />
          <.cmd name="store_keys()" desc="List all keys" />
          <.cmd name="store_delete(key)" desc="Delete a key" />
        </tbody>
      </table>

      <h3>Events</h3>
      <table>
        <thead><tr><th>Command</th><th>Description</th></tr></thead>
        <tbody>
          <.cmd name="watch()" desc="Print live events to IEx console" />
          <.cmd name="unwatch()" desc="Stop printing live events" />
          <.cmd name="events(last: N)" desc="Show recent events (default 20)" />
          <.cmd name="clear_events()" desc="Clear event history" />
        </tbody>
      </table>
      """
    end

    defp cmd(assigns) do
      ~H"""
      <tr>
        <td class="mono" style="white-space: nowrap;">{@name}</td>
        <td class="muted">{@desc}</td>
      </tr>
      """
    end
  end
end
