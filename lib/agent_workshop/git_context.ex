if Code.ensure_loaded?(Git) do
  defmodule AgentWorkshop.GitContext do
    @moduledoc """
    Git context injection for Workshop agents.

    When `git_context: true` is set in `configure/1`, a summary of the
    current git state is automatically appended to every agent's system
    prompt. Agents always know what branch they're on, what's changed,
    and recent commit history.

    ## Usage

        configure(git_context: true)

    ## What's injected

    - Current branch and tracking info
    - Dirty/clean status
    - Staged and unstaged file counts
    - Last 5 commit subjects
    - Uncommitted file list (if dirty)
    """

    @doc """
    Build a git context string for the current working directory.

    Returns a formatted string suitable for appending to an agent's
    system prompt, or `nil` if git info is unavailable.
    """
    @spec build(keyword()) :: String.t() | nil
    def build(opts \\ []) do
      config = build_config(opts)

      with {:ok, info} <- safe_summary(config),
           {:ok, status} <- safe_status(config) do
        format_context(info, status, config)
      else
        _ -> nil
      end
    end

    @doc """
    Get a structured summary of the current git state.

    Returns a map with branch, status, recent commits, and file changes.
    """
    @spec summary(keyword()) :: {:ok, map()} | {:error, term()}
    def summary(opts \\ []) do
      config = build_config(opts)

      with {:ok, info} <- safe_summary(config),
           {:ok, status} <- safe_status(config),
           {:ok, commits} <- safe_log(config, 10) do
        {:ok,
         %{
           branch: info.branch,
           sha: info[:commit],
           dirty: info.dirty,
           ahead: info.ahead,
           behind: info.behind,
           staged: info.staged,
           unstaged: info[:modified] || 0,
           untracked: info.untracked,
           status: status,
           commits: commits
         }}
      end
    end

    @doc """
    Get uncommitted changes as a formatted string.
    """
    @spec changes(keyword()) :: {:ok, String.t()} | {:error, term()}
    def changes(opts \\ []) do
      config = build_config(opts)

      case Git.diff(config: config) do
        {:ok, diff} -> {:ok, diff.raw}
        error -> error
      end
    end

    # ── Internal ──────────────────────────────────────────────

    defp build_config(opts) do
      working_dir = Keyword.get(opts, :working_dir)

      if working_dir do
        Git.Config.new(working_dir: working_dir)
      else
        Git.Config.new()
      end
    end

    defp safe_summary(config) do
      Git.Info.summary(config: config)
    rescue
      _ -> {:error, :git_unavailable}
    end

    defp safe_status(config) do
      Git.status(config: config)
    rescue
      _ -> {:error, :git_unavailable}
    end

    defp safe_log(config, count) do
      Git.log(max_count: count, config: config)
    rescue
      _ -> {:error, :git_unavailable}
    end

    defp format_context(info, status, config) do
      sections = [
        format_branch(info),
        format_tracking(info),
        format_files(info, status),
        format_recent_commits(config)
      ]

      context =
        sections
        |> Enum.reject(&is_nil/1)
        |> Enum.join("\n")

      """
      ## Git Context

      #{context}
      """
      |> String.trim()
    end

    defp format_branch(info) do
      dirty = if info.dirty, do: " (dirty)", else: " (clean)"
      sha = if info[:commit], do: " @ #{String.slice(info.commit, 0..6)}", else: ""
      "Branch: #{info.branch}#{sha}#{dirty}"
    end

    defp format_tracking(info) do
      cond do
        info.ahead > 0 and info.behind > 0 ->
          "Tracking: #{info.ahead} ahead, #{info.behind} behind"

        info.ahead > 0 ->
          "Tracking: #{info.ahead} ahead"

        info.behind > 0 ->
          "Tracking: #{info.behind} behind"

        true ->
          nil
      end
    end

    defp format_files(info, status) do
      modified = info[:modified] || 0

      parts =
        [
          if(info.staged > 0, do: "#{info.staged} staged"),
          if(modified > 0, do: "#{modified} modified"),
          if(info.untracked > 0, do: "#{info.untracked} untracked")
        ]
        |> Enum.reject(&is_nil/1)

      if parts == [] do
        nil
      else
        files =
          status.entries
          |> Enum.take(15)
          |> Enum.map_join("\n", fn entry ->
            "  #{entry.index}#{entry.working_tree} #{entry.path}"
          end)

        "Files: #{Enum.join(parts, ", ")}\n#{files}"
      end
    end

    defp format_recent_commits(config) do
      case safe_log(config, 5) do
        {:ok, commits} when commits != [] ->
          lines =
            commits
            |> Enum.map_join("\n", fn c -> "  #{c.abbreviated_hash} #{c.subject}" end)

          "Recent commits:\n#{lines}"

        _ ->
          nil
      end
    end
  end
end
