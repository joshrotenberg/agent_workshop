---
name: solo
description: Single agent, direct interaction. The simplest Workshop setup. Use for quick tasks, exploration, or when one agent is enough.
license: MIT
metadata:
  author: joshrotenberg
  version: "1.0"
---

# Solo

One agent, one conversation. Use `ask` for back-and-forth, `cast` for background work.

## Setup

```elixir
configure(backend: AgentWorkshop.Backends.Claude,
  backend_config: ClaudeWrapper.Config.new(working_dir: "."),
  model: "sonnet", permission_mode: :bypass_permissions)

agent(:dev, "You are a helpful software engineer.")
```

## Usage

```elixir
ask(:dev, "What's in this project?")
ask(:dev, "Add tests for the retry module")
cast(:dev, "Refactor the config module")
status()
await(:dev)
```

## When to use

- Quick exploration or questions
- Single-focus tasks
- When coordination overhead isn't worth it
