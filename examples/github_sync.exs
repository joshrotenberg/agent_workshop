# GitHub Sync -- poll issues, create board items, create PRs for completed work.
# Requires: gh CLI authenticated (run `gh auth status` to verify).

configure(
  backend: AgentWorkshop.Backends.Claude,
  backend_config: ClaudeWrapper.Config.new(working_dir: "."),
  model: "sonnet",
  permission_mode: :bypass_permissions,
  context: "You sync GitHub issues to the Workshop board and create PRs for completed work.",
  mcp: [port: 4222]
)

agent(:github_sync,
  "You are a GitHub sync agent. You bridge GitHub issues and the Workshop board.",
  workshop_tools: true,
  skill: :github,
  model: "sonnet",
  max_turns: 15
)

every(:github_sync, """
Sync GitHub issues to the board.

1. Run: gh issue list --label "agent" --state open --json number,title,body,labels
2. Run: board() to see existing items
3. For each issue not already on the board (match by id "gh_<number>"):
   - add_work(id: "gh_<number>", title: "<issue title>", type: "triage", priority: 3, spec: "<issue body>")
   - Comment on the issue: gh issue comment <number> --body "Synced to board as gh_<number>"
4. Report what you synced (or "nothing new" if no new issues)

Do NOT re-add issues already on the board in any status.
""", interval: :timer.minutes(5))

# Optional: board workers to process synced issues.
# Uncomment to enable automatic processing.
#
# profile(:coder, "You write clean, well-tested code.", max_turns: 15)
#
# board_worker(:dev_1, :code, profile: :coder,
#   interval: :timer.seconds(30), worktree: true)
#
# When a board worker completes an item, it can create a PR:
#   gh pr create --title "fix: <title>" --body "Closes #<number>"
# The github skill teaches agents how to do this.

# Usage:
#   schedules()          # see sync schedule
#   cast(:github_sync, "Sync now.")  # manual trigger
#   board()              # see synced items
#   workers()            # see worker status (if enabled)
