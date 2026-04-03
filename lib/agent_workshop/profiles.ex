defmodule AgentWorkshop.Profiles do
  @moduledoc """
  Reusable agent templates.

  Define profiles once, instantiate agents from them on demand.
  Useful for orchestrators that spin up ephemeral agents for specific tasks.

  ## Usage

      profile(:coder, "You write clean code.", max_turns: 15)
      profile(:reviewer, "Review only.", model: "opus", allowed_tools: ["Read", "Bash"])

      # Create an agent from a profile
      from_profile(:coder, :coder_bug_42)

      # List available profiles
      profiles()
  """

  @table :agent_workshop_profiles

  @type profile_def :: %{role: String.t() | nil, opts: keyword()}

  @doc false
  def table_name, do: @table

  @doc false
  def create_table do
    if :ets.info(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set])
    end
  end

  @doc false
  def delete_table do
    if :ets.info(@table) != :undefined do
      :ets.delete(@table)
    end
  end

  @doc """
  Define a profile.
  """
  @spec define(atom(), String.t() | nil, keyword()) :: :ok
  def define(name, role \\ nil, opts \\ []) do
    :ets.insert(@table, {name, %{role: role, opts: opts}})
    :ok
  end

  @doc """
  Get a profile definition.
  """
  @spec get(atom()) :: profile_def() | nil
  def get(name) do
    case :ets.lookup(@table, name) do
      [{^name, definition}] -> definition
      [] -> nil
    end
  end

  @doc """
  List all profile names.
  """
  @spec list() :: [atom()]
  def list do
    :ets.tab2list(@table)
    |> Enum.map(&elem(&1, 0))
    |> Enum.sort()
  end

  @doc """
  Remove a profile.
  """
  @spec remove(atom()) :: :ok
  def remove(name) do
    :ets.delete(@table, name)
    :ok
  end

  @doc """
  Clear all profiles.
  """
  @spec clear() :: :ok
  def clear do
    if :ets.info(@table) != :undefined do
      :ets.delete_all_objects(@table)
    end

    :ok
  end
end
