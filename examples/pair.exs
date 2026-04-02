# Pair -- implement and review.
# The classic two-agent workflow: one builds, one reviews.

configure(
  backend: AgentWorkshop.Backends.Claude,
  backend_config: ClaudeWrapper.Config.new(working_dir: "."),
  model: "sonnet",
  permission_mode: :bypass_permissions,
  context: "Focus on clean, well-tested code."
)

agent(:impl, "You write clean, well-tested code.", max_turns: 15)

agent(:reviewer, "You review code. Do not modify files.",
  model: "opus",
  allowed_tools: ["Read", "Bash"]
)

# Usage:
#   ask(:impl, "Implement the caching layer")
#   |> pipe(:reviewer, "Review for edge cases")
