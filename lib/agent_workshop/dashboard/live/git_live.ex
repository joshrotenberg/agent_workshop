if Code.ensure_loaded?(Phoenix.LiveView) and Code.ensure_loaded?(Git) do
  defmodule AgentWorkshop.Dashboard.Live.GitLive do
    @moduledoc false
    use Phoenix.LiveView

    alias AgentWorkshop.GitContext

    @refresh_interval 10_000

    @impl true
    def mount(_params, _session, socket) do
      if connected?(socket) do
        Process.send_after(self(), :refresh, @refresh_interval)
      end

      {:ok, assign(socket, active_tab: :git) |> refresh_data()}
    end

    @impl true
    def handle_info(:refresh, socket) do
      Process.send_after(self(), :refresh, @refresh_interval)
      {:noreply, refresh_data(socket)}
    end

    def handle_info(_, socket), do: {:noreply, socket}

    defp refresh_data(socket) do
      case GitContext.summary() do
        {:ok, summary} ->
          assign(socket,
            available: true,
            branch: summary.branch,
            sha: summary.sha,
            dirty: summary.dirty,
            ahead: summary.ahead,
            behind: summary.behind,
            staged: summary.staged,
            unstaged: summary.unstaged,
            untracked: summary.untracked,
            files: summary.status.entries,
            commits: summary.commits
          )

        _ ->
          assign(socket, available: false)
      end
    end

    @impl true
    def render(assigns) do
      ~H"""
      <h2>Git</h2>

      <%= if !@available do %>
        <p class="muted">Not in a git repository, or git dep not available.</p>
      <% else %>
        <div>
          <div class="stat">
            <div class="stat-value">{@branch}</div>
            <div class="stat-label">Branch</div>
          </div>
          <div class="stat">
            <div class={"stat-value #{if @dirty, do: "cost", else: ""}"}>
              {if @dirty, do: "dirty", else: "clean"}
            </div>
            <div class="stat-label">Status</div>
          </div>
          <%= if @ahead > 0 do %>
            <div class="stat">
              <div class="stat-value">{@ahead}</div>
              <div class="stat-label">Ahead</div>
            </div>
          <% end %>
          <%= if @behind > 0 do %>
            <div class="stat">
              <div class="stat-value">{@behind}</div>
              <div class="stat-label">Behind</div>
            </div>
          <% end %>
          <div class="stat">
            <div class="stat-value">{@staged}</div>
            <div class="stat-label">Staged</div>
          </div>
          <div class="stat">
            <div class="stat-value">{@unstaged}</div>
            <div class="stat-label">Modified</div>
          </div>
          <div class="stat">
            <div class="stat-value">{@untracked}</div>
            <div class="stat-label">Untracked</div>
          </div>
        </div>

        <%= if @files != [] do %>
          <h3>Changed Files</h3>
          <table>
            <thead>
              <tr><th>Index</th><th>Work</th><th>Path</th></tr>
            </thead>
            <tbody>
              <%= for entry <- Enum.take(@files, 30) do %>
                <tr>
                  <td class="mono">{status_char(entry.index)}</td>
                  <td class="mono">{status_char(entry.working_tree)}</td>
                  <td class="mono">{entry.path}</td>
                </tr>
              <% end %>
              <%= if length(@files) > 30 do %>
                <tr><td colspan="3" class="muted">... and {length(@files) - 30} more</td></tr>
              <% end %>
            </tbody>
          </table>
        <% end %>

        <h3>Recent Commits</h3>
        <%= if @commits == [] do %>
          <p class="muted">No commits.</p>
        <% else %>
          <table>
            <thead>
              <tr><th>Hash</th><th>Author</th><th>Subject</th></tr>
            </thead>
            <tbody>
              <%= for commit <- @commits do %>
                <tr>
                  <td class="mono" style="color: #58a6ff;">{commit.abbreviated_hash}</td>
                  <td class="muted">{commit.author_name}</td>
                  <td>{commit.subject}</td>
                </tr>
              <% end %>
            </tbody>
          </table>
        <% end %>
      <% end %>
      """
    end

    defp status_char(" "), do: " "
    defp status_char("?"), do: "?"
    defp status_char(c), do: c
  end
end
