# AgentWorkshop

[![CI](https://github.com/joshrotenberg/agent_workshop/actions/workflows/ci.yml/badge.svg)](https://github.com/joshrotenberg/agent_workshop/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/agent_workshop.svg)](https://hex.pm/packages/agent_workshop)
[![Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/agent_workshop)

Multi-agent orchestration for IEx. Backend-agnostic, MCP-enabled.

Run multiple LLM agents side by side, coordinate them with simple
commands, and expose them as MCP tools. Works with Claude, Codex,
or any CLI-based LLM through a pluggable backend.

## Installation

```elixir
def deps do
  [
    {:agent_workshop, "~> 0.2"},

    # Pick your backend(s):
    {:claude_wrapper, "~> 0.4"},   # for Claude Code CLI
    {:codex_wrapper, "~> 0.2"},    # for OpenAI Codex CLI

    # Optional, for MCP server:
    {:anubis_mcp, "~> 1.0"},
    {:bandit, "~> 1.0"},
    {:plug, "~> 1.16"}
  ]
end
```

## Quick start

```
$ iex -S mix
```

```elixir
import AgentWorkshop.Workshop

configure(
  backend: AgentWorkshop.Backends.Claude,
  backend_config: ClaudeWrapper.Config.new(working_dir: "."),
  model: "sonnet",
  permission_mode: :bypass_permissions,
  context: "Elixir project. Run mix test before committing."
)

agent(:impl, "You write clean, well-tested code.", max_turns: 15)
agent(:reviewer, "You review code. Do not modify files.",
  model: "opus", allowed_tools: ["Read", "Bash"])

ask(:impl, "Implement caching for the user lookup")
|> pipe(:reviewer, "Review for correctness")
```

## Setup files

Put agent configuration in `.workshop.exs` and it auto-loads on `iex -S mix`:

```elixir
# .workshop.exs
configure(
  backend: AgentWorkshop.Backends.Claude,
  backend_config: ClaudeWrapper.Config.new(working_dir: "."),
  model: "sonnet",
  permission_mode: :bypass_permissions,
  context: "My project description.",
  mcp: [port: 4222]
)

profile(:coder, "You write clean code.", max_turns: 15)
profile(:reviewer, "Review only.", model: "opus", allowed_tools: ["Read", "Bash"])

agent(:orchestrator, "You coordinate agents.",
  workshop_tools: true, model: "sonnet", max_turns: 30)
```

## Three orchestration patterns

### 1. Direct (ask/cast/pipe)

```elixir
ask(:impl, "Implement the retry logic")
cast(:impl, "Implement the caching layer")
status()
await(:impl)

ask(:impl, "Implement caching")
|> pipe(:reviewer, "Review for edge cases")
|> pipe(:tests, "Write tests for this")
```

### 2. Orchestrator (workshop_tools + profiles)

An agent with `workshop_tools: true` can create and manage other agents:

```elixir
profile(:coder, "You write clean code.", max_turns: 15)
profile(:reviewer, "Review only.", model: "opus")

agent(:orchestrator, "You coordinate agents.",
  workshop_tools: true, model: "sonnet", max_turns: 30)

cast(:orchestrator, "Build the auth module, have it reviewed and tested")
# Orchestrator creates coders from profiles, delegates, reviews, cleans up
```

### 3. Board workers (post work, agents self-organize)

```elixir
profile(:coder, "You write clean code.", max_turns: 15)
profile(:reviewer, "Review only.", model: "opus")

board_worker(:coder_1, :code, profile: :coder, interval: :timer.seconds(30))
board_worker(:coder_2, :code, profile: :coder, interval: :timer.seconds(30))
board_worker(:reviewer_1, :review, profile: :reviewer, interval: :timer.seconds(30))

# Post work -- workers pick it up automatically
work(:feature, "Implement checkout command", type: :code, priority: 1,
  spec: "Follow existing patterns. Write tests.")
work(:feature_review, "Review checkout", type: :review, depends_on: [:feature])
# coder claims feature, implements it, marks done
# feature_review auto-unblocks, reviewer claims it
```

## Work board

Structured task tracker with lifecycle and dependencies:

```elixir
work(:cache, "Implement LRU cache", type: :code, priority: 1,
  spec: "LRU with 1000 entries and TTL per entry")
work(:cache_review, "Review cache", type: :review, depends_on: [:cache])

board()                    # show all items
board(status: :ready)      # filter by status
claim_work(:cache, :impl)  # manually claim
complete_work(:cache)      # mark done, unblocks dependents
```

Lifecycle: `new -> ready -> claimed -> in_progress -> done / failed / blocked / cancelled`

## Shared state

Key-value scratchpad for agent coordination:

```elixir
put(:spec, "LRU cache with TTL support")
get(:spec)
store()          # show all entries
store_keys()     # list keys
```

## Event log

See what's happening in real time:

```elixir
watch()              # print events live
events()             # show last 20 events
events(last: 50)     # more
```

## Scheduling

Run prompts on a recurring interval:

```elixir
every(:monitor, "Check CI status", interval: :timer.minutes(5))
schedules()
cancel(:monitor)
```

## Cost budgets

```elixir
configure(max_cost_usd: 10.00)
agent(:impl, "Coder", max_cost_usd: 2.00)
budget()          # global remaining
budget(:impl)     # per-agent
```

## Agent timeouts

```elixir
agent(:impl, "Coder", timeout: :timer.minutes(5))
# Returns {:error, :timeout} if CLI doesn't respond in time
```

## MCP server

Expose Workshop as MCP tools so Claude Code can orchestrate agents:

```elixir
mcp_server(port: 4222)
```

Then in `.mcp.json`:

```json
{
  "mcpServers": {
    "workshop": {
      "type": "http",
      "url": "http://localhost:4222/mcp"
    }
  }
}
```

21 tools available including agent management, work board, and coordination.

## Skills

Skills follow the [agentskills.io](https://agentskills.io) open standard.
Agents with `workshop_tools: true` auto-receive AGENTS.md guidance.

```elixir
agent(:impl, "Coder", skill: :pair)
agent(:orchestrator, "Coordinator", workshop_tools: true)  # gets AGENTS.md
```

## Observability

```elixir
status()                       # dashboard table
info(:impl)                    # detailed map
result(:impl)                  # last response text
result(:impl, :full)           # full result map
history(:impl)                 # conversation
cost()                         # itemized by agent
total_cost()                   # sum
watch()                        # live event stream
events()                       # event history
workers()                      # board worker status
board()                        # work board
```

## Backends

| Backend | Package | CLI |
|---|---|---|
| `AgentWorkshop.Backends.Claude` | `claude_wrapper` | Claude Code |
| `AgentWorkshop.Backends.Codex` | `codex_wrapper` | OpenAI Codex |

Implement `AgentWorkshop.Backend` to add your own.

## Examples

See `examples/` for ready-to-use `.workshop.exs` configs and
`skills/` for agentskills.io-format pattern guides.

## License

MIT -- see [LICENSE](LICENSE).
