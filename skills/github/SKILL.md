---
name: github
description: GitHub integration via gh CLI. List issues, create PRs, comment on issues. Use for agents that bridge GitHub and the Workshop board.
license: MIT
metadata:
  author: joshrotenberg
  version: "1.0"
---

# GitHub

Bridge GitHub issues and PRs with the Workshop board using the `gh` CLI.

## Prerequisites

Verify authentication before any operation:

```bash
gh auth status
```

## Reading issues

```bash
# List open issues with a label
gh issue list --label "agent" --state open --json number,title,body,labels --limit 50

# Read a single issue
gh issue view 42 --json number,title,body,labels,comments
```

Always use `--json` for structured output.

## Board integration

When syncing issues to the board, use the ID convention `gh_<number>` for dedup:

```elixir
# Check if already on the board before adding
board()

# Add a new work item from an issue
add_work(id: "gh_42", title: "Issue title", type: "triage", priority: 3,
  spec: "Issue body text here")
```

Skip issues that already have a board item (any status).

## Creating PRs

After work is completed on a branch:

```bash
# Create PR linking back to the issue
gh pr create --title "fix: description" --body "Closes #42" --head branch-name --base main
```

Use `Closes #N` in the PR body to auto-close the issue on merge.

## Commenting and labeling

```bash
# Status update on an issue
gh issue comment 42 --body "Picked up by agent, work item gh_42 created."

# Label management
gh issue edit 42 --add-label "in-progress"
gh issue edit 42 --remove-label "agent"
```

## When to use

- Sync GitHub issues to the board for agent processing
- Create PRs from completed board work
- Keep issue status in sync with board state
