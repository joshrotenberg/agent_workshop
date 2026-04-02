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
    {:agent_workshop, "~> 0.1.0"},

    # Pick your backend(s):
    {:claude_wrapper, "~> 0.5"},   # for Claude Code CLI
    {:codex_wrapper, "~> 0.1"},    # for OpenAI Codex CLI

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

# Configure with your backend
configure(
  backend: AgentWorkshop.Backends.Claude,
  backend_config: ClaudeWrapper.Config.new(working_dir: "."),
  model: "sonnet",
  permission_mode: :bypass_permissions,
  context: "Elixir project. Run mix test before committing."
)

# Create agents
agent(:impl, "You write clean, well-tested code.", max_turns: 15)
agent(:reviewer, "You review code. Do not modify files.",
  model: "opus", allowed_tools: ["Read", "Bash"])

# Talk to them
ask(:impl, "Implement caching for the user lookup")
|> pipe(:reviewer, "Review for correctness")

# Check on things
status()
total_cost()
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
  mcp: [port: 4222]  # auto-start MCP server
)

agent(:impl, "You write clean code.", max_turns: 15)
agent(:reviewer, "Review only.", model: "opus", allowed_tools: ["Read", "Bash"])
```

## Sync vs async

```elixir
# Synchronous -- blocks until done
ask(:impl, "Implement the retry logic")

# Asynchronous -- returns immediately
cast(:impl, "Implement the caching layer")
cast(:tests, "Write tests for lib/encoder.ex")

status()        # see who's done
await(:impl)    # wait for one
await_all()     # wait for everyone
```

## Coordination

```elixir
# Pipe: chain agents together
ask(:impl, "Implement caching")
|> pipe(:reviewer, "Review for edge cases")
|> pipe(:tests, "Write tests for this")

# Fan: same question to multiple agents
fan("What issues do you see in lib/retry.ex?", [:impl, :reviewer])
await_all()
result(:impl)       # impl's take
result(:reviewer)   # reviewer's take
```

## Mixed backends

Different LLMs for different roles:

```elixir
configure(
  backend: AgentWorkshop.Backends.Claude,
  backend_config: ClaudeWrapper.Config.new(working_dir: ".")
)

agent(:impl, "You write code.", model: "sonnet")
agent(:reviewer, "You review code.",
  backend: AgentWorkshop.Backends.Codex,
  backend_config: CodexWrapper.Config.new(working_dir: "."),
  model: "o3"
)
```

## MCP server

Expose Workshop as MCP tools so Claude Code can orchestrate agents:

```elixir
# Start MCP server (or use mcp: [port: 4222] in configure)
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

15 tools available: `configure`, `create_agent`, `ask`, `cast`, `await`,
`await_all`, `status`, `result`, `pipe`, `fan`, `info`, `agents`,
`reset`, `dismiss`, `cost`.

## Observability

```elixir
status()                       # dashboard table
info(:impl)                    # detailed map (model, cost, turns, ...)
result(:impl)                  # last response text
result(:impl, :full)           # full result map
history(:impl)                 # print conversation
history(:impl, last: 3)        # last 3 turns
cost()                         # itemized by agent
total_cost()                   # one number
```

## Lifecycle

```elixir
reset(:impl)     # clear conversation, keep config
dismiss(:impl)   # remove agent entirely
reset_all()      # stop everything
load("other.exs") # load a different setup
```

## Backends

| Backend | Package | CLI |
|---|---|---|
| `AgentWorkshop.Backends.Claude` | `claude_wrapper` | Claude Code |
| `AgentWorkshop.Backends.Codex` | `codex_wrapper` | OpenAI Codex |

Implement `AgentWorkshop.Backend` to add your own. See the behaviour
module for the 8 required callbacks.

## Examples

See `examples/` for ready-to-use `.workshop.exs` configs:

- `solo.exs` -- single agent
- `pair.exs` -- implement + review
- `team.exs` -- impl, reviewer, tests, docs
- `mixed.exs` -- Claude + Codex agents together

## License

MIT -- see [LICENSE](LICENSE).
