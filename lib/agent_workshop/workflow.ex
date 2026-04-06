defmodule AgentWorkshop.Workflow do
  @moduledoc """
  Declarative workflows -- staged pipelines with file inputs.

  A workflow defines a sequence of stages, each assigned to an agent or profile.
  Stages can depend on previous stages (result piping) or read from files.
  Under the hood, workflows expand into work board items with dependencies,
  so board workers execute them automatically.

  ## Defining a workflow

      workflow(:feature, [
        {:plan, :planner, "Break this into tasks", from: "specs/feature.md"},
        {:implement, :coder, "Implement the plan", from: :plan},
        {:test, :tester, "Write tests", from: :implement},
        {:review, :reviewer, "Review everything", from: [:implement, :test]}
      ])

  ## Running

      run_workflow(:feature)       # expands stages into work items
      workflow_status(:feature)    # check progress
      reset_workflow(:feature)     # clear and re-run

  ## Stage options

  - `from: "path/to/file.md"` -- read file content into spec
  - `from: :stage_name` -- pipe previous stage's result
  - `from: [:a, :b]` -- fan-in from multiple stages
  - `type: :code` -- work board type (default: :custom)
  - `priority: 1` -- priority (default: 3)
  """

  alias AgentWorkshop.{PubSub, Work}

  @table :agent_workshop_workflows

  defstruct [:name, :stages, :created_at, status: :defined]

  @type stage :: %{
          name: atom(),
          work_id: atom(),
          agent: atom(),
          title: String.t(),
          type: atom(),
          priority: non_neg_integer(),
          depends_on: [atom()],
          from_stages: [atom()],
          file_input: String.t() | nil
        }

  @type t :: %__MODULE__{
          name: atom(),
          stages: [stage()],
          created_at: DateTime.t(),
          status: :defined | :running | :completed | :failed
        }

  # ── Table management ────────────────────────────────────────

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

  # ── Public API ─────────────────────────────────────────────

  @doc """
  Define a workflow. Validates and stores the stage definitions.
  """
  @spec define(atom(), list()) :: :ok | {:error, term()}
  def define(name, stages) when is_atom(name) and is_list(stages) do
    case parse_stages(name, stages) do
      {:ok, parsed} ->
        workflow = %__MODULE__{
          name: name,
          stages: parsed,
          created_at: DateTime.utc_now()
        }

        :ets.insert(@table, {name, workflow})
        PubSub.broadcast({:workflow, :defined, name})
        :ok

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Run a workflow by expanding its stages into work board items.
  """
  @spec run(atom()) :: :ok | {:error, term()}
  def run(name) do
    case get(name) do
      nil ->
        {:error, :not_found}

      %{status: :running} ->
        {:error, :already_running}

      workflow ->
        expand_stages(workflow)
        update_status(name, :running)
        PubSub.broadcast({:workflow, :started, name})
        :ok
    end
  end

  @doc """
  Reset a workflow -- removes all its work items and sets status back to :defined.
  """
  @spec reset(atom()) :: :ok | {:error, term()}
  def reset(name) do
    case get(name) do
      nil ->
        {:error, :not_found}

      workflow ->
        for stage <- workflow.stages do
          Work.remove(stage.work_id)
        end

        update_status(name, :defined)
        PubSub.broadcast({:workflow, :reset, name})
        :ok
    end
  end

  @doc """
  Get a workflow definition.
  """
  @spec get(atom()) :: t() | nil
  def get(name) do
    case :ets.lookup(@table, name) do
      [{^name, workflow}] -> workflow
      [] -> nil
    end
  end

  @doc """
  Get workflow status with all stage items.
  """
  @spec status(atom()) :: {t(), [Work.t() | nil]} | {:error, :not_found}
  def status(name) do
    case get(name) do
      nil ->
        {:error, :not_found}

      workflow ->
        items = Enum.map(workflow.stages, fn s -> Work.get(s.work_id) end)
        {workflow, items}
    end
  end

  @doc """
  List all defined workflows.
  """
  @spec list() :: [t()]
  def list do
    :ets.tab2list(@table)
    |> Enum.map(&elem(&1, 1))
    |> Enum.sort_by(& &1.name)
  end

  @doc """
  Check if a workflow is complete (all stages done) and update status.
  Called after a work item completes to detect workflow completion.
  """
  @spec check_completion(atom()) :: :ok
  def check_completion(name) do
    case get(name) do
      %{status: :running} = workflow ->
        items = Enum.map(workflow.stages, fn s -> Work.get(s.work_id) end)

        cond do
          Enum.all?(items, fn item -> item && item.status == :done end) ->
            update_status(name, :completed)
            PubSub.broadcast({:workflow, :completed, name})

          Enum.any?(items, fn item -> item && item.status in [:failed, :blocked] end) ->
            update_status(name, :failed)
            PubSub.broadcast({:workflow, :failed, name})

          true ->
            :ok
        end

      _ ->
        :ok
    end
  end

  @doc """
  Find which workflow (if any) a work item belongs to.
  """
  @spec workflow_for_item(atom()) :: atom() | nil
  def workflow_for_item(item_id) do
    case Work.get(item_id) do
      %{metadata: %{workflow: name}} -> name
      _ -> nil
    end
  end

  # ── Serialization ──────────────────────────────────────────

  @doc false
  def to_map(%__MODULE__{} = workflow) do
    %{
      "name" => Atom.to_string(workflow.name),
      "status" => Atom.to_string(workflow.status),
      "created_at" => if(workflow.created_at, do: DateTime.to_iso8601(workflow.created_at)),
      "stages" =>
        Enum.map(workflow.stages, fn s ->
          %{
            "name" => Atom.to_string(s.name),
            "work_id" => Atom.to_string(s.work_id),
            "agent" => Atom.to_string(s.agent),
            "title" => s.title,
            "type" => Atom.to_string(s.type),
            "priority" => s.priority,
            "depends_on" => Enum.map(s.depends_on, &Atom.to_string/1),
            "from_stages" => Enum.map(s.from_stages, &Atom.to_string/1),
            "file_input" => s.file_input
          }
        end)
    }
  end

  @doc false
  def from_map(map) do
    %__MODULE__{
      name: String.to_atom(map["name"]),
      status: String.to_atom(map["status"]),
      created_at: parse_datetime(map["created_at"]),
      stages:
        Enum.map(map["stages"] || [], fn s ->
          %{
            name: String.to_atom(s["name"]),
            work_id: String.to_atom(s["work_id"]),
            agent: String.to_atom(s["agent"]),
            title: s["title"],
            type: String.to_atom(s["type"]),
            priority: s["priority"] || 3,
            depends_on: Enum.map(s["depends_on"] || [], &String.to_atom/1),
            from_stages: Enum.map(s["from_stages"] || [], &String.to_atom/1),
            file_input: s["file_input"]
          }
        end)
    }
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  # ── Internal ───────────────────────────────────────────────

  defp parse_stages(workflow_name, stages) do
    parsed =
      Enum.map(stages, fn
        {stage_name, agent, title} ->
          parse_stage(workflow_name, stage_name, agent, title, [])

        {stage_name, agent, title, opts} when is_list(opts) ->
          parse_stage(workflow_name, stage_name, agent, title, opts)

        other ->
          {:error, {:invalid_stage, other}}
      end)

    case Enum.find(parsed, &match?({:error, _}, &1)) do
      nil -> {:ok, parsed}
      error -> error
    end
  end

  defp parse_stage(workflow_name, stage_name, agent, title, opts) do
    from = Keyword.get(opts, :from)
    type = Keyword.get(opts, :type, :custom)
    priority = Keyword.get(opts, :priority, 3)
    work_id = :"#{workflow_name}_#{stage_name}"

    {depends_on, from_stages, file_input} = resolve_from(workflow_name, from)

    %{
      name: stage_name,
      work_id: work_id,
      agent: agent,
      title: title,
      type: type,
      priority: priority,
      depends_on: depends_on,
      from_stages: from_stages,
      file_input: file_input
    }
  end

  defp resolve_from(_wf, nil), do: {[], [], nil}

  defp resolve_from(_wf, path) when is_binary(path), do: {[], [], path}

  defp resolve_from(wf, stage) when is_atom(stage) do
    id = :"#{wf}_#{stage}"
    {[id], [id], nil}
  end

  defp resolve_from(wf, stages) when is_list(stages) do
    ids = Enum.map(stages, &:"#{wf}_#{&1}")
    {ids, ids, nil}
  end

  defp expand_stages(workflow) do
    for stage <- workflow.stages do
      spec = build_spec(stage)

      Work.add(stage.work_id, stage.title,
        type: stage.type,
        priority: stage.priority,
        spec: spec,
        depends_on: stage.depends_on,
        metadata: %{workflow: workflow.name, from_stages: stage.from_stages, agent: stage.agent}
      )
    end
  end

  defp build_spec(%{file_input: path} = stage) when is_binary(path) do
    case File.read(path) do
      {:ok, content} ->
        if stage.from_stages != [] do
          content
        else
          content
        end

      {:error, reason} ->
        "Error reading #{path}: #{inspect(reason)}"
    end
  end

  defp build_spec(_stage), do: nil

  defp update_status(name, status) do
    case get(name) do
      nil -> :ok
      workflow -> :ets.insert(@table, {name, %{workflow | status: status}})
    end
  end
end
