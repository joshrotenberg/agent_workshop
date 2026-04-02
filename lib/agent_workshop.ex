defmodule AgentWorkshop do
  @moduledoc """
  Multi-agent orchestration for IEx. Backend-agnostic, MCP-enabled.

  AgentWorkshop lets you run multiple LLM agents side by side,
  coordinating them with simple IEx commands. It works with any
  CLI-based LLM backend (Claude, Codex, etc.) through a pluggable
  backend behaviour.

  ## Quick start

      import AgentWorkshop.Workshop

      configure(
        backend: AgentWorkshop.Backends.Claude,
        backend_config: ClaudeWrapper.Config.new(working_dir: "."),
        model: "sonnet",
        context: "Elixir project. Run mix test before committing."
      )

      agent(:impl, "You write clean code.", max_turns: 15)
      agent(:reviewer, "Review only.", model: "opus")

      ask(:impl, "Implement caching")
      |> pipe(:reviewer, "Review for edge cases")

  ## Mixed backends

      agent(:claude_impl, "You write code.", backend: AgentWorkshop.Backends.Claude)
      agent(:codex_reviewer, "Review only.", backend: AgentWorkshop.Backends.Codex)

  ## Backends

    * `AgentWorkshop.Backends.Claude` - Claude Code CLI (requires `claude_wrapper`)
    * `AgentWorkshop.Backends.Codex` - OpenAI Codex CLI (requires `codex_wrapper`)

  See `AgentWorkshop.Backend` to implement your own.
  """
end
