# Monitor — scheduled agent for periodic checks.

configure(
  backend: AgentWorkshop.Backends.Claude,
  backend_config: ClaudeWrapper.Config.new(working_dir: "."),
  model: "haiku",
  permission_mode: :bypass_permissions,
  context: "You monitor project health."
)

agent(:monitor, "You check project health and report issues concisely.",
  model: "haiku",
  max_turns: 3
)

every(:monitor, "Run mix test and report: pass/fail count, any failures.",
  interval: :timer.minutes(10)
)

# Usage:
#   schedules()     # see active schedules
#   status()        # check agent state
#   result(:monitor) # last check result
#   cancel(:monitor) # stop monitoring
