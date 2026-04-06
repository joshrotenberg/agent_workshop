# Getting Started

AgentWorkshop is a multi-agent orchestration library for Elixir. You create
LLM agents, give them roles, and coordinate their work -- all from IEx.

## Prerequisites

AgentWorkshop runs CLI-based LLM tools on your behalf. You need at least one
installed and authenticated:

- **[Claude Code](https://docs.anthropic.com/en/docs/claude-code)** -- `claude`
  CLI, authenticated via `claude login`. This is the recommended backend.
- **[OpenAI Codex](https://github.com/openai/codex)** -- `codex` CLI, with
  `OPENAI_API_KEY` set. Alternative backend.

Agents run these CLIs as your user, with your credentials and permissions.
They can read and write files, run shell commands, and make git commits --
just like you would from the terminal. Use `permission_mode` and
`allowed_tools` to control what agents can do.

For source control features (git context injection, worktrees for parallel
agents, GitHub integration):

- **git** -- any recent version
- **[gh](https://cli.github.com/)** -- GitHub CLI, authenticated via
  `gh auth login`. Needed for the GitHub integration skill.

## Installation

Add `agent_workshop` and a backend to your `mix.exs`:

```elixir
def deps do
  [
    {:agent_workshop, "~> 0.3"},
    {:claude_wrapper, "~> 0.4"}  # Claude Code CLI backend
  ]
end
```

Optional dependencies unlock additional features:

```elixir
# MCP server (expose Workshop as tools for other agents)
{:anubis_mcp, "~> 1.0"},
{:bandit, "~> 1.0"},
{:plug, "~> 1.16"},

# LiveView dashboard (real-time web UI)
{:phoenix, "~> 1.7"},
{:phoenix_live_view, "~> 1.0"},
{:phoenix_html, "~> 4.0"},

# Git context injection
{:git, "~> 0.2"},

# Alternative backend
{:codex_wrapper, "~> 0.2"}  # OpenAI Codex CLI
```

## First session

Start IEx in your project:

```
$ iex -S mix
```

Import the Workshop API and configure your backend:

```elixir
import AgentWorkshop.Workshop

configure(
  backend: AgentWorkshop.Backends.Claude,
  backend_config: ClaudeWrapper.Config.new(working_dir: "."),
  model: "sonnet",
  permission_mode: :bypass_permissions,
  context: "Elixir project. Run mix test before committing."
)
```

## Creating agents

Each agent has a name and a role description that becomes its system prompt:

```elixir
agent(:impl, "You write clean, well-tested code.", max_turns: 15)
agent(:reviewer, "You review code. Do not modify files.",
  model: "opus", allowed_tools: ["Read", "Bash"])
```

## Talking to agents

`ask/2` sends a message and waits for a response:

```elixir
ask(:impl, "Implement caching for the user lookup")
```

`cast/2` sends a message and returns immediately. The agent works in the
background:

```elixir
cast(:impl, "Implement the retry logic from issue #12")
status()       # see who's working
await(:impl)   # wait for the result
```

## Piping results

Chain agents together with `pipe/3`. The result from one agent is forwarded
to the next:

```elixir
ask(:impl, "Implement caching")
|> pipe(:reviewer, "Review for edge cases")
|> pipe(:impl, "Address the review feedback")
```

## Setup files

Instead of configuring manually each time, put your setup in `.workshop.exs`:

```elixir
# .workshop.exs -- auto-loaded on iex -S mix
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

Load a different setup file at any time:

```elixir
load("examples/board.exs")
```

## Checking on things

```elixir
status()           # agent dashboard
info(:impl)        # detailed info for one agent
result(:impl)      # last response text
cost()             # cost breakdown by agent
total_cost()       # total spend
history(:impl)     # full conversation
```

## Next steps

- [Orchestration Patterns](orchestration-patterns.md) -- three ways to coordinate agents
- [Work Board and Workflows](work-board.md) -- structured task management
- [MCP Server](mcp-server.md) -- expose Workshop as tools
- [Configuration Reference](configuration.md) -- all options explained
