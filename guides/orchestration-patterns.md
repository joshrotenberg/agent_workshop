# Orchestration Patterns

AgentWorkshop supports three patterns for coordinating agents. Each builds on
the previous -- start simple and add structure as your tasks grow.

## 1. Direct (ask/cast/pipe)

You control the flow. Send messages, read results, decide what happens next.

```elixir
# Synchronous -- blocks until the agent responds
ask(:impl, "Implement caching for user lookups")

# Asynchronous -- agent works in background
cast(:impl, "Implement the retry module")
cast(:tests, "Write property-based tests for lib/encoder.ex")
status()        # see who's working
await_all()     # wait for everyone

# Chaining -- pipe results from one agent to another
ask(:impl, "Implement caching")
|> pipe(:reviewer, "Review for correctness")
|> pipe(:impl, "Address the review feedback")

# Fan out -- same question to multiple agents
fan("What issues do you see in lib/retry.ex?", [:impl, :reviewer])
await_all()
result(:impl)       # one perspective
result(:reviewer)    # another perspective
```

**When to use:** Exploratory work, one-off tasks, debugging sessions. You're
actively driving the conversation and making judgment calls between steps.

## 2. Orchestrator (workshop_tools + profiles)

A dedicated agent creates and manages other agents. You give it a high-level
goal and it breaks it down, delegates, and coordinates.

```elixir
# Define reusable agent templates
profile(:coder, "You write clean, well-tested code.",
  max_turns: 15, timeout: :timer.minutes(5))
profile(:reviewer, "Review for correctness. Do not modify files.",
  model: "opus", allowed_tools: ["Read", "Bash"])

# Create the orchestrator with MCP access to Workshop
agent(:orchestrator, "You coordinate a team of agents to build features.",
  workshop_tools: true, model: "sonnet", max_turns: 30)

# Give it a goal -- it handles the rest
cast(:orchestrator, """
Build the auth module:
1. Create a coder from the :coder profile
2. Have it implement JWT-based authentication
3. Create a reviewer from the :reviewer profile
4. Have it review the implementation
5. Address any feedback
""")
```

The orchestrator has access to 21 MCP tools for creating agents, sending
messages, managing the work board, and checking status. See the
[MCP Server guide](mcp-server.md) for the full tool list.

**When to use:** Multi-step features where you want an agent to manage the
workflow. Good for tasks with clear success criteria that don't need human
judgment at each step.

## 3. Board workers (self-organizing)

Post work items to a board. Workers poll for items matching their type,
claim them, execute them, and mark them done. Dependencies handle ordering.

```elixir
# Define roles
profile(:coder, "You write clean code.", max_turns: 15)
profile(:reviewer, "Review only.", model: "opus")

# Start workers -- they poll the board automatically
board_worker(:dev_1, :code, profile: :coder,
  interval: :timer.seconds(30), worktree: true)
board_worker(:dev_2, :code, profile: :coder,
  interval: :timer.seconds(30), worktree: true)
board_worker(:rev_1, :review, profile: :reviewer,
  interval: :timer.seconds(30))

# Post work -- workers pick it up
work(:auth, "Implement auth module", type: :code, priority: 1,
  spec: "JWT-based auth with login/logout endpoints")
work(:auth_review, "Review auth", type: :review, depends_on: [:auth])

work(:api, "Implement API routes", type: :code, priority: 2,
  spec: "REST endpoints for users and posts")
work(:api_review, "Review API", type: :review, depends_on: [:api])

# Watch it happen
watch()          # live event stream
board()          # current state
workers()        # worker status
```

Workers use `worktree: true` to work in isolated git worktrees, so multiple
coders can work on different items in parallel without conflicts.

**When to use:** Multiple independent tasks, parallel execution, CI-like
pipelines. The board handles coordination so you just post work and observe.

## 4. Declarative workflows

Define multi-stage pipelines as data. Each stage runs an agent and feeds
its result to the next. Under the hood, workflows expand into board items
with dependencies.

```elixir
workflow(:feature, [
  {:plan, :planner, "Break this into tasks", from: "specs/feature.md"},
  {:implement, :coder, "Implement the plan", from: :plan, type: :code},
  {:test, :tester, "Write tests", from: :implement, type: :test},
  {:review, :reviewer, "Review everything", from: [:implement, :test], type: :review}
])

run_workflow(:feature)
workflow_status(:feature)
```

Workflows support file inputs (`from: "path"`), stage chaining (`from: :stage`),
and fan-in (`from: [:a, :b]`). See the [Work Board guide](work-board.md) for
details.

**When to use:** Repeatable processes with clear stages. Define once, run
many times. Good for structured development workflows (plan, implement,
test, review).

## Choosing a pattern

| Pattern | Control | Automation | Complexity |
|---------|---------|------------|------------|
| Direct | Full | None | Low |
| Orchestrator | Delegated | High | Medium |
| Board workers | Observed | Full | Medium |
| Workflows | Declarative | Full | Low |

Start with **direct** for exploration. Move to **workflows** when you have a
repeatable process. Use **board workers** when you need parallel execution.
Use an **orchestrator** when the task requires dynamic judgment calls that
you don't want to make yourself.

These patterns compose. An orchestrator can post work to the board. A workflow
can include stages that use orchestrator agents. Board workers execute
workflow stages automatically.
