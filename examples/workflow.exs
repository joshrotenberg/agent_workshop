# Workflow -- declarative multi-stage pipeline.
# Stages run in dependency order. Results flow automatically.

configure(
  backend: AgentWorkshop.Backends.Claude,
  backend_config: ClaudeWrapper.Config.new(working_dir: "."),
  model: "sonnet",
  permission_mode: :bypass_permissions,
  context: "Software project. Follow existing patterns."
)

# Profiles for each role
profile(:planner, "You break features into concrete implementation tasks.",
  model: "sonnet",
  max_turns: 5
)

profile(:coder, "You write clean, well-tested code.",
  max_turns: 15,
  timeout: :timer.minutes(5)
)

profile(:tester, "You write thorough tests. Run them and fix failures.",
  max_turns: 10,
  timeout: :timer.minutes(3)
)

profile(:reviewer, "Review for correctness, edge cases, and style. Do not modify files.",
  model: "opus",
  allowed_tools: ["Read", "Bash"]
)

# Define the pipeline
workflow(:feature, [
  {:plan, :planner, "Break this feature into implementation tasks"},
  {:implement, :coder, "Implement the plan", from: :plan, type: :code},
  {:test, :tester, "Write tests for the implementation", from: :implement, type: :test},
  {:review, :reviewer, "Review implementation and tests",
   from: [:implement, :test], type: :review}
])

# Board workers to execute stages
board_worker(:dev_1, :code, profile: :coder, interval: :timer.seconds(30), worktree: true)
board_worker(:dev_2, :test, profile: :tester, interval: :timer.seconds(30), worktree: true)
board_worker(:rev_1, :review, profile: :reviewer, interval: :timer.seconds(30))

# Usage:
#   # Start the pipeline (first stage has no deps, runs immediately)
#   run_workflow(:feature)
#
#   # Watch progress
#   workflow_status(:feature)
#   board()
#   watch()
#
#   # Re-run after changes
#   reset_workflow(:feature)
#   run_workflow(:feature)
