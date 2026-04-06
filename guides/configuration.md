# Configuration Reference

All Workshop configuration is set through `configure/1` or individual
functions. Configuration is stored in `:persistent_term` for zero-cost reads.

## configure/1

```elixir
configure(
  backend: AgentWorkshop.Backends.Claude,
  backend_config: ClaudeWrapper.Config.new(working_dir: "."),
  model: "sonnet",
  permission_mode: :bypass_permissions,
  context: "Elixir project. Run mix test before committing.",
  max_cost_usd: 10.00,
  mcp: [port: 4222],
  dashboard: true,
  persistence: true,
  git_context: true
)
```

### Required options

| Option | Description |
|--------|-------------|
| `:backend` | Backend module (e.g., `AgentWorkshop.Backends.Claude`) |
| `:backend_config` | Backend-specific configuration struct |

### Agent defaults

These apply to all agents unless overridden per-agent:

| Option | Default | Description |
|--------|---------|-------------|
| `:model` | (none) | LLM model name (e.g., `"sonnet"`, `"opus"`, `"haiku"`) |
| `:permission_mode` | `:auto` | `:default`, `:accept_edits`, `:bypass_permissions`, `:dont_ask`, `:plan`, `:auto` |
| `:context` | (none) | System prompt prepended to all agents |
| `:max_cost_usd` | (none) | Global cost budget across all agents |

### Feature toggles

| Option | Default | Description |
|--------|---------|-------------|
| `:mcp` | (none) | Start MCP server. Pass `[port: 4222]` or just `true` for default port. |
| `:dashboard` | `false` | Start LiveView dashboard on port 4223 |
| `:persistence` | `false` | Enable disk persistence. Pass `true` for `.agent_workshop/` or a path string. |
| `:git_context` | `false` | Inject git branch, status, and recent commits into agent prompts |

## Agent options

Options passed to `agent/3` override global defaults:

```elixir
agent(:impl, "You write clean, well-tested code.",
  model: "sonnet",
  max_turns: 15,
  timeout: :timer.minutes(5),
  max_cost_usd: 2.00,
  allowed_tools: ["Read", "Edit", "Write", "Bash"],
  skill: :pair,
  workshop_tools: true
)
```

| Option | Description |
|--------|-------------|
| `:model` | Override model for this agent |
| `:max_turns` | Maximum conversation turns |
| `:timeout` | Response timeout in milliseconds |
| `:max_cost_usd` | Per-agent cost budget |
| `:allowed_tools` | Restrict which tools the agent can use |
| `:skill` | Assign a skill from `skills/` (e.g., `:pair`, `:board`) |
| `:workshop_tools` | `true` to give the agent MCP access to Workshop |
| `:permission_mode` | Override permission mode for this agent |

## Profiles

Profiles are reusable agent templates. Define once, create many agents:

```elixir
profile(:coder, "You write clean, well-tested code.",
  model: "sonnet",
  max_turns: 15,
  timeout: :timer.minutes(5))

profile(:reviewer, "Review for correctness. Do not modify files.",
  model: "opus",
  allowed_tools: ["Read", "Bash"])

# Create agents from profiles
from_profile(:coder, :dev_1)
from_profile(:coder, :dev_2)
from_profile(:reviewer, :rev_1)

# Or use profiles with board workers
board_worker(:dev_1, :code, profile: :coder, interval: :timer.seconds(30))
```

Manage profiles:

```elixir
profiles()              # list all profiles
```

## Backends

A backend implements `AgentWorkshop.Backend` -- 8 callbacks for starting
sessions, sending messages, and reading state.

### Claude (recommended)

```elixir
configure(
  backend: AgentWorkshop.Backends.Claude,
  backend_config: ClaudeWrapper.Config.new(working_dir: ".")
)
```

The Claude backend wraps the Claude Code CLI via `claude_wrapper`. Backend
config options are passed through to `ClaudeWrapper.Config`.

### Codex

```elixir
configure(
  backend: AgentWorkshop.Backends.Codex,
  backend_config: CodexWrapper.Config.new(working_dir: ".")
)
```

### Custom backends

Implement the `AgentWorkshop.Backend` behaviour:

```elixir
defmodule MyBackend do
  @behaviour AgentWorkshop.Backend

  @impl true
  def start_session(config, opts), do: ...
  @impl true
  def send_message(pid, prompt, opts), do: ...
  @impl true
  def session_id(pid), do: ...
  @impl true
  def history(pid), do: ...
  @impl true
  def total_cost(pid), do: ...
  @impl true
  def turn_count(pid), do: ...
  @impl true
  def last_result(pid), do: ...
  @impl true
  def stop_session(pid), do: ...
end
```

## Budgets

Set cost limits globally or per-agent:

```elixir
# Global budget
configure(max_cost_usd: 10.00)

# Per-agent budget
agent(:impl, "Coder", max_cost_usd: 2.00)

# Check budgets
budget()         # global remaining
budget(:impl)    # per-agent
cost()           # itemized by agent
total_cost()     # total across all agents
```

When a budget is exceeded, the agent's next message returns
`{:error, :budget_exceeded}`.

## Persistence

Persist work board, store, and events to disk:

```elixir
configure(persistence: true)              # .agent_workshop/ in cwd
configure(persistence: "/path/to/dir")    # custom directory
```

### Files written

- `work.json` -- full work board snapshot
- `store.json` -- key-value store snapshot
- `workflows.json` -- workflow definitions
- `events.jsonl` -- append-only event log

Writes are debounced (100ms) and triggered by PubSub events. On startup
with persistence enabled, saved state is loaded back into ETS.

## Git context

Automatically inject git state into agent prompts:

```elixir
configure(git_context: true)
```

This appends the current branch, working tree status, and recent commits
to each agent's system prompt. The context is refreshed on each message.
Requires the optional `{:git, "~> 0.2"}` dependency.

```elixir
# Manual access
git_summary()    # structured map of git state
git_diff()       # current diff text
```

## Scheduling

Run prompts on a recurring interval:

```elixir
every(:monitor, "Check CI status and report",
  interval: :timer.minutes(5))

schedules()         # list active schedules
cancel(:monitor)    # stop a schedule
```

The scheduler skips ticks when the agent is busy.

## Event log

All Workshop activity is logged to a ring buffer:

```elixir
watch()              # print events live (PubSub subscription)
unwatch()            # stop watching
events()             # last 20 events
events(last: 50)     # more history
clear_events()       # reset the ring buffer
```

Events include agent creation/dismissal, ask/cast completions, work board
changes, board worker claims, and workflow state transitions.

## Shared store

Key-value scratchpad for agent coordination:

```elixir
put(:spec, "LRU cache with TTL support")
get(:spec)
store()              # show all entries
store_keys()         # list keys
delete(:spec)
```

Values are stored in ETS and optionally persisted to disk.

## Skills

Skills follow the [agentskills.io](https://agentskills.io) open standard.
Skill content is injected into the agent's system prompt:

```elixir
agent(:impl, "Coder", skill: :pair)
```

Built-in skills (in `skills/`):

| Skill | Description |
|-------|-------------|
| `:solo` | Single agent working alone |
| `:pair` | Implement + review pattern |
| `:board` | Work board driven development |
| `:"board-worker"` | Polling agent pattern |
| `:orchestrator` | Team coordinator |
| `:monitor` | Scheduled health checks |
| `:mixed` | Multiple backend agents |
| `:workflow` | Multi-stage pipelines |
| `:github` | GitHub integration via gh CLI |

## Log level

Control Workshop log verbosity:

```elixir
log_level(:warning)    # quiet -- only warnings and errors
log_level(:info)       # default
log_level(:debug)      # verbose -- see send/receive for every message
```

## Teardown

```elixir
reset(:impl)       # clear one agent's conversation
dismiss(:impl)     # remove an agent
reset_all()        # stop all agents, clear config
stop()             # full teardown (agents, tables, config)
```

## Examples

The `examples/` directory contains ready-to-use setup files:

| File | Pattern |
|------|---------|
| `solo.exs` | Single agent |
| `pair.exs` | Implement + review |
| `board.exs` | Board workers |
| `workflow.exs` | Declarative workflow |
| `orchestrator.exs` | Orchestrator with MCP |
| `monitor.exs` | Scheduled monitoring |
| `budget.exs` | Cost budgets |
| `mixed.exs` | Multiple backends |
| `team.exs` | Multi-agent team |
| `github_sync.exs` | GitHub issue sync |
| `dogfood.exs` | Self-referential setup |

Load any example:

```elixir
load("examples/board.exs")
```
