defmodule AgentWorkshop.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/joshrotenberg/agent_workshop"

  def project do
    [
      app: :agent_workshop,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package(),
      name: "AgentWorkshop",
      description: "Multi-agent orchestration from IEx. Backend-agnostic, MCP-enabled.",
      dialyzer: [
        plt_file: {:no_warn, "_build/dev/dialyxir_#{System.otp_release()}.plt"}
      ],
      releases: releases()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {AgentWorkshop.Application, []}
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.2"},
      {:cheer, "~> 0.1.3"},
      # Backends -- optional, users pick what they need
      {:claude_wrapper, "~> 0.4", optional: true},
      {:codex_wrapper, "~> 0.2", optional: true},
      {:git, "~> 0.2", optional: true},
      {:anubis_mcp, "~> 1.0", optional: true},
      {:bandit, "~> 1.0", optional: true},
      {:plug, "~> 1.16", optional: true},
      # Dashboard -- optional LiveView UI
      {:phoenix, "~> 1.7", optional: true},
      {:phoenix_live_view, "~> 1.0", optional: true},
      {:phoenix_html, "~> 4.0", optional: true},
      # Binary packaging -- optional
      {:burrito, "~> 1.0", optional: true},
      {:ex_doc, "~> 0.35", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      extras: [
        "README.md",
        "guides/getting-started.md",
        "guides/orchestration-patterns.md",
        "guides/work-board.md",
        "guides/mcp-server.md",
        "guides/configuration.md",
        "CHANGELOG.md",
        "LICENSE"
      ],
      groups_for_extras: [
        Guides: ~r/guides\/.*/
      ],
      groups_for_modules: [
        "Core API": [
          AgentWorkshop,
          AgentWorkshop.Workshop,
          AgentWorkshop.Backend
        ],
        Backends: [
          AgentWorkshop.Backends.Claude,
          AgentWorkshop.Backends.Codex
        ],
        "Work Board": [
          AgentWorkshop.Work,
          AgentWorkshop.BoardWorker,
          AgentWorkshop.Workflow
        ],
        "Agent Configuration": [
          AgentWorkshop.Profiles,
          AgentWorkshop.Skills,
          AgentWorkshop.Budget
        ],
        Observability: [
          AgentWorkshop.EventLog,
          AgentWorkshop.PubSub,
          AgentWorkshop.Telemetry
        ],
        Infrastructure: [
          AgentWorkshop.Store,
          AgentWorkshop.Scheduler,
          AgentWorkshop.Persistence,
          AgentWorkshop.GitContext
        ]
      ]
    ]
  end

  defp releases do
    [
      aw: [
        steps: [:assemble, &Burrito.wrap/1],
        burrito: [
          targets: [
            macos: [os: :darwin, cpu: :x86_64],
            macos_m1: [os: :darwin, cpu: :aarch64],
            linux: [os: :linux, cpu: :x86_64]
          ]
        ]
      ]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib skills examples AGENTS.md mix.exs README.md LICENSE .formatter.exs),
      maintainers: ["Josh Rotenberg"]
    ]
  end
end
