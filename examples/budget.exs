# Budget — cost-controlled exploration.
# Set limits so agents can't run away with your wallet.

configure(
  backend: AgentWorkshop.Backends.Claude,
  backend_config: ClaudeWrapper.Config.new(working_dir: "."),
  model: "sonnet",
  permission_mode: :bypass_permissions,
  max_cost_usd: 5.00,
  context: "Explore the codebase. Be concise."
)

agent(:explorer, "You explore code and answer questions.",
  max_cost_usd: 2.00,
  max_turns: 10
)

agent(:deep_dive, "You do deep analysis when asked.",
  model: "opus",
  max_cost_usd: 3.00,
  max_turns: 5
)

# Usage:
#   ask(:explorer, "What's the architecture of this project?")
#   budget(:explorer)   # check remaining
#   budget()            # global remaining
#   total_cost()        # how much spent so far
