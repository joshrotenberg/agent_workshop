# Solo agent -- simplest setup.
# One agent, one backend, just start talking.

configure(
  backend: AgentWorkshop.Backends.Claude,
  backend_config: ClaudeWrapper.Config.new(working_dir: "."),
  model: "sonnet",
  permission_mode: :bypass_permissions
)

agent(:dev, "You are a helpful software engineer.")
