configure(
  backend: AgentWorkshop.Backends.Claude,
  backend_config: ClaudeWrapper.Config.new(working_dir: "."),
  model: "sonnet",
  permission_mode: :bypass_permissions,
  context: "agent_workshop - Multi-agent orchestration for IEx. Elixir project.",
  mcp: [port: 4222]
)

agent(:impl, "You write clean, well-tested Elixir code.", max_turns: 15)

agent(:reviewer, "Code review only. Do not modify files.",
  model: "opus",
  allowed_tools: ["Read", "Bash"]
)
