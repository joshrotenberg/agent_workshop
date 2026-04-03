# Orchestrator — coordinator agent delegates to specialist team.
# The orchestrator has Workshop tools and creates agents from profiles.

configure(
  backend: AgentWorkshop.Backends.Claude,
  backend_config: ClaudeWrapper.Config.new(working_dir: "."),
  model: "sonnet",
  permission_mode: :bypass_permissions,
  context: "Software project. Follow existing patterns. Run tests before reporting done.",
  mcp: [port: 4222]
)

profile(:coder, "You write clean, well-tested code. Always include tests.", max_turns: 15)

profile(:reviewer, "You review code. Do not modify files. Report findings as a prioritized list.",
  model: "opus",
  allowed_tools: ["Read", "Bash"]
)

agent(:orchestrator,
  "You coordinate a team of agents. Use Workshop tools to delegate work.",
  workshop_tools: true,
  model: "sonnet",
  max_turns: 30
)

# Usage:
#   cast(:orchestrator, "Build the auth module with tests. Have it reviewed.")
#   status()
#   events()
