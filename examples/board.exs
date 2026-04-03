# Board — post work items, board workers self-organize.
# Workers poll the board, claim ready items, execute, mark done.
# Dependencies auto-unblock when predecessors complete.

configure(
  backend: AgentWorkshop.Backends.Claude,
  backend_config: ClaudeWrapper.Config.new(working_dir: "."),
  model: "sonnet",
  permission_mode: :bypass_permissions,
  context: "Software project. Follow existing patterns. Run tests before reporting done."
)

profile(:coder, "You write clean, well-tested code.", max_turns: 15, timeout: :timer.minutes(5))
profile(:reviewer, "Review only. Do not modify files.", model: "opus", allowed_tools: ["Read", "Bash"])

# Two parallel coders + one reviewer
board_worker(:coder_1, :code, profile: :coder, interval: :timer.seconds(30), worktree: true)
board_worker(:coder_2, :code, profile: :coder, interval: :timer.seconds(30), worktree: true)
board_worker(:reviewer_1, :review, profile: :reviewer, interval: :timer.seconds(30))

# Usage:
#   watch()
#
#   work(:auth, "Implement auth module", type: :code, priority: 1,
#     spec: "JWT-based auth with login/logout endpoints")
#   work(:auth_review, "Review auth", type: :review, depends_on: [:auth])
#
#   work(:api, "Implement API routes", type: :code, priority: 2,
#     spec: "REST endpoints for users and posts")
#   work(:api_review, "Review API", type: :review, depends_on: [:api])
#
#   board()     # watch items flow through
#   workers()   # see worker status
#   events()    # full timeline
