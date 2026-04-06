# MCP Server

AgentWorkshop includes an MCP (Model Context Protocol) server that exposes
the Workshop API as tools. Any MCP client -- including Claude Code, other
agents, or custom clients -- can connect and manage agents, work items,
and coordination.

## Setup

### Dependencies

Add the MCP dependencies to your `mix.exs`:

```elixir
{:anubis_mcp, "~> 1.0"},
{:bandit, "~> 1.0"},
{:plug, "~> 1.16"}
```

### Starting the server

Start the MCP server from IEx or a setup file:

```elixir
# From IEx
mcp_server(port: 4222)

# Or via configure/1 (auto-starts with your setup)
configure(
  backend: AgentWorkshop.Backends.Claude,
  backend_config: ClaudeWrapper.Config.new(working_dir: "."),
  mcp: [port: 4222]
)
```

### Client configuration

Point your MCP client at the server. For Claude Code, add to `.mcp.json`:

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

## Available tools (21)

### Agent management (6 tools)

| Tool | Description |
|------|-------------|
| `configure` | Set backend, model, context, and other global options |
| `create_agent` | Create an agent with a name and role |
| `from_profile` | Create an agent from a saved profile |
| `agents` | List all agents and their status |
| `reset` | Clear an agent's conversation (keep role and config) |
| `dismiss` | Remove an agent entirely |

### Interaction (6 tools)

| Tool | Description |
|------|-------------|
| `ask` | Send a message and wait for the response |
| `cast` | Send a message asynchronously |
| `await` | Wait for an async agent to finish |
| `await_all` | Wait for all busy agents to finish |
| `pipe` | Forward one agent's result to another |
| `fan` | Send the same message to multiple agents |

### Work board (5 tools)

| Tool | Description |
|------|-------------|
| `add_work` | Add a work item to the board |
| `board` | List work items (optionally filtered) |
| `claim_work` | Claim a work item for an agent |
| `complete_work` | Mark a work item as done |
| `fail_work` | Mark a work item as failed |

### Observability (4 tools)

| Tool | Description |
|------|-------------|
| `status` | Agent dashboard (names, status, cost, turns) |
| `result` | Get an agent's last response |
| `info` | Detailed info for one agent |
| `cost` | Cost breakdown across all agents |

## Orchestrator pattern

The MCP server enables the orchestrator pattern -- an agent with
`workshop_tools: true` that can create and manage other agents:

```elixir
profile(:coder, "You write clean code.", max_turns: 15)
profile(:reviewer, "Review only.", model: "opus")

agent(:orchestrator, "You coordinate agents to build features.",
  workshop_tools: true, model: "sonnet", max_turns: 30)

cast(:orchestrator, "Build the auth module with review")
```

When an agent has `workshop_tools: true`, its backend config is automatically
set up to connect to the MCP server. The orchestrator can then:

1. Create agents from profiles (`from_profile`)
2. Send them work (`ask`, `cast`)
3. Monitor progress (`status`, `result`)
4. Manage the work board (`add_work`, `board`, `complete_work`)
5. Clean up when done (`dismiss`)

The `AGENTS.md` file at the project root provides guidance to orchestrator
agents about available tools and recommended patterns.

## Skills for MCP-aware agents

Agents with `workshop_tools: true` automatically receive the `AGENTS.md`
guidance. You can also assign skills for specific patterns:

```elixir
agent(:coordinator, "You manage the team.",
  workshop_tools: true, skill: :orchestrator)
```

See `skills/orchestrator/SKILL.md` for the orchestrator skill guide.

## Dashboard

If you have the Phoenix LiveView dependencies installed, you can also
start the web dashboard alongside the MCP server:

```elixir
configure(
  mcp: [port: 4222],
  dashboard: true
)
```

The dashboard runs on port 4223 and provides real-time views of agents,
the work board, workers, configuration, git status, and a reference guide.
