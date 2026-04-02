---
name: board
description: Work board driven development. Post typed work items with dependencies, agents poll by role. Use for multi-step features where ordering matters.
license: MIT
metadata:
  author: joshrotenberg
  version: "1.0"
---

# Board

Structured task tracker. Work items have types, dependencies, and lifecycle states. Agents claim work matching their role.

## Setup

```elixir
agent(:coder, "Check the board for :code items. Claim one, implement it, mark done.",
  work_types: [:code])
agent(:reviewer, "Check the board for :review items. Claim one, review it.",
  work_types: [:review])
```

## Usage

```elixir
# Post work
work(:cache, "Implement LRU cache", type: :code, priority: 1,
  spec: "LRU with TTL, max 1000 entries")
work(:cache_review, "Review cache", type: :review, depends_on: [:cache])
work(:cache_tests, "Test cache", type: :test, depends_on: [:cache])

# Check board
board()
board(status: :ready)

# Agents claim and advance
claim_work(:cache, :coder)
start_work(:cache)
complete_work(:cache, "Done with GenServer-backed LRU")
# :cache_review and :cache_tests auto-unblock to :ready
```

## When to use

- Multi-step features with natural ordering
- Multiple agents working on different aspects
- You want visibility into what's done and what's pending
- Work is organic — items can be added mid-flight

## Board vs pipe

**Pipe**: you control the flow manually. A then B then C.
**Board**: agents self-organize. Dependencies handle ordering. New work can be added anytime.
