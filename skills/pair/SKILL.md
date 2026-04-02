---
name: pair
description: Implement-then-review pattern. Two agents collaborating via pipe chains. Use when you need a second perspective on code changes.
license: MIT
metadata:
  author: joshrotenberg
  version: "1.0"
---

# Pair

Two agents: one builds, one reviews. Connected via `pipe`.

## Setup

```elixir
agent(:impl, "You write clean, well-tested code.", max_turns: 15)
agent(:reviewer, "You review code. Do not modify files.",
  model: "opus", allowed_tools: ["Read", "Bash"])
```

## Usage

```elixir
ask(:impl, "Implement the caching layer")
|> pipe(:reviewer, "Review for edge cases")

# If reviewer finds issues:
ask(:impl, "Address this feedback: #{result(:reviewer)}")
|> pipe(:reviewer, "Check if the issues are resolved")
```

## When to use

- You have a clear task and want quality assurance
- Changes are focused enough for one agent to implement
- You want review feedback before moving on

## Agent guidance

**If you are the implementor**: Write code, include tests, run them before reporting. Be specific about what you changed and why.

**If you are the reviewer**: Read the diff carefully. Report findings as a prioritized list. Do not modify files. Focus on correctness, edge cases, and style.
