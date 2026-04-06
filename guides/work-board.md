# Work Board and Workflows

The work board is a structured task tracker. Work items flow through a
lifecycle, dependencies handle ordering, and board workers execute items
automatically.

## Work items

A work item has a name, title, type, and optional spec:

```elixir
work(:cache, "Implement LRU cache",
  type: :code,
  priority: 1,
  spec: "LRU cache with configurable max size and TTL per entry")
```

### Types

Work types let you route items to the right workers:

- `:code` -- implementation work
- `:review` -- code review
- `:test` -- test writing
- `:docs` -- documentation
- `:deploy` -- deployment tasks
- `:triage` -- issue triage
- `:custom` -- anything else (default)

### Priority

Priority ranges from 1 (highest) to 5 (lowest). Default is 3. Board workers
claim the highest-priority ready item first.

## Lifecycle

Every work item moves through these states:

```
new --> ready --> claimed --> in_progress --> done
                                          --> failed
              ^
        blocked (unmet dependency)
        cancelled
```

- **new** -- has unmet dependencies, waiting
- **ready** -- all dependencies satisfied, available for claim
- **claimed** -- an agent claimed it but hasn't started yet
- **in_progress** -- actively being worked on
- **done** -- completed successfully, unblocks downstream
- **failed** -- execution failed, blocks downstream
- **blocked** -- a dependency failed or was cancelled
- **cancelled** -- manually cancelled

## Dependencies

Items can depend on other items. Dependents stay in `:new` until all
dependencies reach `:done`:

```elixir
work(:cache, "Implement LRU cache", type: :code)
work(:cache_tests, "Write cache tests", type: :test, depends_on: [:cache])
work(:cache_review, "Review cache", type: :review, depends_on: [:cache])
```

When `:cache` completes, both `:cache_tests` and `:cache_review` automatically
transition to `:ready`. If `:cache` fails, both are `:blocked`.

## Board commands

```elixir
board()                    # show all items
board(status: :ready)      # filter by status
board(type: :code)         # filter by type

claim_work(:cache, :impl)  # manually claim for an agent
start_work(:cache)         # mark in progress
complete_work(:cache, "Implemented with GenServer-backed LRU")
fail_work(:cache, "tests broken")
cancel_work(:cache)        # cancel and block dependents
```

## Board workers

A board worker combines an agent profile with a poll loop. It watches the
board for ready items matching its type, claims them, executes them, and
marks them done or failed.

```elixir
profile(:coder, "You write clean code.", max_turns: 15)
profile(:reviewer, "Review only.", model: "opus")

board_worker(:dev_1, :code,
  profile: :coder,
  interval: :timer.seconds(30),
  worktree: true)

board_worker(:rev_1, :review,
  profile: :reviewer,
  interval: :timer.seconds(30))
```

### Options

- `:profile` (required) -- profile to create the agent from
- `:interval` -- poll interval in milliseconds (default: 60,000)
- `:worktree` -- when `true`, the agent works in an isolated git worktree

### Monitoring

```elixir
workers()    # show all workers and their current item
watch()      # live event stream (claims, completions, failures)
events()     # recent event history
```

Workers reset their agent session between items so each task starts with
a fresh conversation.

## Declarative workflows

Workflows define multi-stage pipelines as data. Each stage is a work item
with automatic dependency wiring and result flow.

### Defining a workflow

```elixir
workflow(:feature, [
  {:plan, :planner, "Break this into tasks", from: "specs/feature.md"},
  {:implement, :coder, "Implement the plan", from: :plan, type: :code},
  {:test, :tester, "Write tests", from: :implement, type: :test},
  {:review, :reviewer, "Review everything", from: [:implement, :test], type: :review}
])
```

Each stage is a tuple: `{name, agent, title}` or `{name, agent, title, opts}`.

### Stage options

- `from: "path/to/file.md"` -- read file content and inject as the stage's spec
- `from: :stage_name` -- the previous stage's result is injected into the prompt
- `from: [:a, :b]` -- fan-in: combine results from multiple stages
- `type: :code` -- work board type for routing to the right worker
- `priority: 1` -- priority (default: 3)

### Running

```elixir
run_workflow(:feature)       # expand stages into work items
workflow_status(:feature)    # check progress
workflows()                  # list all workflows
```

### Result flow

When a stage completes, its result is automatically injected into the
prompt for any dependent stage. Board workers handle this transparently --
the downstream stage sees a "Previous stage results" section in its prompt.

### Reset and re-run

If a stage fails or you want to iterate:

```elixir
reset_workflow(:feature)     # clear all work items
run_workflow(:feature)       # start fresh
```

### Failure propagation

Workflows are transactional. If a stage fails:

1. The failed stage is marked `:failed`
2. All downstream stages are `:blocked` (via dependency resolution)
3. The workflow status becomes `:failed`

Use `reset_workflow/1` to clear the failed state and try again.

### Workflow lifecycle

```
defined --> running --> completed
                    --> failed
```

A workflow is `:completed` when all stages reach `:done`. It is `:failed`
when any stage is `:failed` or `:blocked`.

## work_from_result

Convert an agent's last response into a work item:

```elixir
ask(:planner, "What should we build?")
work_from_result(:planner, :feature,
  type: :code,
  title: "Implement the feature")
```

The agent's response becomes the work item's spec. Useful for bridging
direct interaction into board-driven execution.
