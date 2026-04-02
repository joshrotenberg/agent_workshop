---
name: mixed
description: Multiple LLM backends in one workshop. Claude and Codex agents working together. Use when different models have different strengths.
license: MIT
metadata:
  author: joshrotenberg
  version: "1.0"
---

# Mixed Backends

Different LLMs for different roles. Same Workshop API regardless of backend.

## Setup

```elixir
configure(backend: AgentWorkshop.Backends.Claude,
  backend_config: ClaudeWrapper.Config.new(working_dir: "."))

agent(:impl, "You write code.", model: "sonnet")
agent(:reviewer, "Review only.",
  backend: AgentWorkshop.Backends.Codex,
  backend_config: CodexWrapper.Config.new(working_dir: "."),
  model: "o3")
```

## When to use

- Different models excel at different tasks
- You want multiple perspectives from different LLMs
- Cost optimization (cheaper model for simple tasks)
