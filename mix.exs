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
      description: "Multi-agent orchestration from IEx. Backend-agnostic, MCP-enabled."
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.2"},
      # Backends -- optional, users pick what they need
      {:claude_wrapper, "~> 0.3", optional: true},
      {:codex_wrapper, "~> 0.2", optional: true},
      {:anubis_mcp, "~> 1.0", optional: true},
      {:bandit, "~> 1.0", optional: true},
      {:plug, "~> 1.16", optional: true},
      {:ex_doc, "~> 0.35", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp docs do
    [
      main: "AgentWorkshop",
      source_url: @source_url
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib mix.exs README.md LICENSE .formatter.exs),
      maintainers: ["Josh Rotenberg"]
    ]
  end
end
