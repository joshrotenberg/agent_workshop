# Mixed backends -- Claude and Codex agents working together.
# Different LLMs for different strengths.

configure(
  backend: AgentWorkshop.Backends.Claude,
  backend_config: ClaudeWrapper.Config.new(working_dir: "."),
  model: "sonnet",
  permission_mode: :bypass_permissions,
  context: "Full-stack project with Rust backend and React frontend."
)

# Claude agents for implementation and review
agent(:impl, "You write clean, well-tested code.", max_turns: 15)

agent(:reviewer, "Code review only. Do not modify files.",
  model: "opus",
  allowed_tools: ["Read", "Bash"]
)

# Codex agent for a second perspective
agent(:codex, "You are a code reviewer with deep systems knowledge.",
  backend: AgentWorkshop.Backends.Codex,
  backend_config: CodexWrapper.Config.new(working_dir: "."),
  model: "o3"
)

# Usage:
#   ask(:impl, "Implement the retry logic")
#   fan("Review this for correctness", [:reviewer, :codex])
#   await_all()
#   result(:reviewer)   # Claude's review
#   result(:codex)      # Codex's review
