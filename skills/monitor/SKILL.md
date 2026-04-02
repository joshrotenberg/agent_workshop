---
name: monitor
description: Scheduled agent for periodic checks. Use for CI monitoring, PR scanning, health checks, or any polling-based workflow.
license: MIT
metadata:
  author: joshrotenberg
  version: "1.0"
---

# Monitor

A scheduled agent that runs a prompt on a recurring interval.

## Setup

```elixir
agent(:monitor, "You check project health and report issues.")
every(:monitor, "Check CI status. Report any failures.", interval: :timer.minutes(5))
```

## Usage

```elixir
schedules()          # list active schedules
cancel(:monitor)     # stop
```

## When to use

- CI status monitoring
- Scanning for unreviewed PRs
- Periodic health checks
- Polling for external events
