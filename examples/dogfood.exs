# Dogfood — use Workshop to build Workshop.
# A fixer agent that works on the agent_workshop project itself.

configure(
  backend: AgentWorkshop.Backends.Claude,
  backend_config: ClaudeWrapper.Config.new(working_dir: "."),
  model: "sonnet",
  permission_mode: :bypass_permissions,
  context: """
  agent_workshop — multi-agent orchestration for IEx.
  Elixir project. Run mix test, mix compile --warnings-as-errors,
  and mix credo --strict before reporting done.
  """,
  mcp: [port: 4222]
)

agent(:fixer, "You fix bugs and add features in Elixir projects.",
  model: "sonnet",
  max_turns: 15,
  timeout: :timer.minutes(5)
)

agent(:reviewer, "You review code. Do not modify files.",
  model: "opus",
  allowed_tools: ["Read", "Bash"]
)

# Usage:
#   watch()
#   ask(:fixer, "Fix issue #42: suppress debug logs in MCP transport")
#   pipe(:fixer, :reviewer, "Review this fix")
