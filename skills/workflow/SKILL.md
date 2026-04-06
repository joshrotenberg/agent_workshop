---
name: workflow
description: Declarative multi-stage workflows. Define staged pipelines where each stage feeds its result to the next. Use for structured multi-agent tasks.
license: MIT
metadata:
  author: joshrotenberg
  version: "1.0"
---

# Workflow

Declarative multi-stage pipelines. Define stages, run them, board workers execute in dependency order.

## Defining a workflow

```elixir
workflow(:feature, [
  {:plan, :planner, "Break this into tasks", from: "specs/feature.md"},
  {:implement, :coder, "Implement the plan", from: :plan},
  {:test, :tester, "Write tests", from: :implement},
  {:review, :reviewer, "Review everything", from: [:implement, :test]}
])
```

Each stage is `{name, agent, title}` or `{name, agent, title, opts}`.

## Stage options

- `from: "path/to/file.md"` -- read file content as input
- `from: :stage_name` -- use previous stage's result as input
- `from: [:a, :b]` -- fan-in: combine results from multiple stages
- `type: :code` -- work board type (default: :custom)
- `priority: 1` -- priority 1 (high) to 5 (low)

## Running

```elixir
run_workflow(:feature)       # expand stages into work items
workflow_status(:feature)    # check progress
reset_workflow(:feature)     # clear and start over
workflows()                  # list all workflows
```

## How it works

- Each stage becomes a work board item with `depends_on`
- Board workers claim and execute stages in order
- Results from completed stages are injected into the next stage's prompt
- If a stage fails, downstream stages are blocked
- Workflow is complete when all stages are done

## When to use

- Multi-step features with clear ordering (plan, implement, test, review)
- Pipelines where each step needs the previous step's output
- Structured delegation across multiple agent roles
- Repeatable processes you want to define once and run many times

## Workflow vs board vs pipe

- **Pipe**: manual, synchronous, you control each step
- **Board**: self-organizing, agents claim work, no fixed ordering
- **Workflow**: declarative, fixed stage ordering, automatic result flow
