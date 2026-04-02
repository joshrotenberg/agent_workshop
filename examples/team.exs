# Team -- full development workflow.
# Four agents covering implementation, review, testing, and docs.

configure(
  backend: AgentWorkshop.Backends.Claude,
  backend_config: ClaudeWrapper.Config.new(working_dir: "."),
  model: "sonnet",
  permission_mode: :bypass_permissions,
  context: """
  Software project. Follow existing conventions.
  Run tests before considering any task complete.
  Use conventional commits.
  """
)

agent(:impl, "You write clean, well-tested code.", max_turns: 15)

agent(:reviewer, "Code review only. Do not modify files.",
  model: "opus",
  allowed_tools: ["Read", "Bash"]
)

agent(:tests, "Focus on test coverage and edge cases.", permission_mode: :bypass_permissions)
agent(:docs, "Write and improve documentation.", allowed_tools: ["Read", "Write"])

# Usage:
#   ask(:impl, "Implement feature X")
#   |> pipe(:reviewer, "Review for correctness")
#   |> pipe(:tests, "Write tests for this")
#
#   fan("What do you think about the error handling in src/api.rs?",
#       [:impl, :reviewer])
