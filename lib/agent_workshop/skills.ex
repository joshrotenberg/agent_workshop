defmodule AgentWorkshop.Skills do
  @moduledoc """
  Loads skill content and AGENTS.md for injection into agent system prompts.

  Skills are markdown files following the agentskills.io format, stored
  in the `skills/` directory of the agent_workshop package.

  AGENTS.md provides top-level context for any agent with Workshop tools.
  """

  @doc """
  Load the AGENTS.md content from the package.
  """
  @spec agents_md() :: String.t() | nil
  def agents_md do
    load_file("AGENTS.md")
  end

  @doc """
  Load a skill's SKILL.md content by name.
  """
  @spec skill(atom()) :: String.t() | nil
  def skill(name) do
    load_file(Path.join(["skills", to_string(name), "SKILL.md"]))
  end

  @doc """
  List available skill names.
  """
  @spec list() :: [atom()]
  def list do
    skills_dir = Path.join(package_root(), "skills")

    if File.dir?(skills_dir) do
      skills_dir
      |> File.ls!()
      |> Enum.filter(fn name ->
        dir = Path.join(skills_dir, name)
        File.dir?(dir) and File.exists?(Path.join(dir, "SKILL.md"))
      end)
      |> Enum.map(&String.to_atom/1)
      |> Enum.sort()
    else
      []
    end
  end

  @doc """
  Build context string for an agent based on its role.

  For `workshop_tools: true` agents, includes the orchestrator section
  from AGENTS.md. For agents with a `:skill` option, includes that
  skill's content.
  """
  @spec context_for(keyword()) :: String.t() | nil
  def context_for(opts) do
    workshop_tools = Keyword.get(opts, :workshop_tools, false)
    skill_name = Keyword.get(opts, :skill)

    parts =
      [
        if(workshop_tools, do: agents_md()),
        if(skill_name, do: skill(skill_name))
      ]
      |> Enum.reject(&is_nil/1)

    case parts do
      [] -> nil
      parts -> Enum.join(parts, "\n\n---\n\n")
    end
  end

  # ── Internal ────────────────────────────────────────────────

  defp load_file(relative_path) do
    path = Path.join(package_root(), relative_path)

    case File.read(path) do
      {:ok, content} -> content
      {:error, _} -> nil
    end
  end

  defp package_root do
    # Try the project root first (development), then the compiled app path
    project_root = Path.join([__DIR__, "..", ".."]) |> Path.expand()

    if File.exists?(Path.join(project_root, "AGENTS.md")) do
      project_root
    else
      Application.app_dir(:agent_workshop)
    end
  end
end
