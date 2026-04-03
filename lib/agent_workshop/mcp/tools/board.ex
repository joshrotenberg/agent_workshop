if Code.ensure_loaded?(Anubis.Server) do
  defmodule AgentWorkshop.MCP.Tools.AddWork do
    @moduledoc false
    use Anubis.Server.Component, type: :tool
    alias Anubis.Server.Response

    schema do
      field(:id, :string, required: true, description: "work item ID")
      field(:title, :string, required: true, description: "work item title")
      field(:type, :string, description: "work type: code, review, test, docs, deploy, triage")
      field(:spec, :string, description: "detailed specification")
      field(:priority, :integer, description: "1 (highest) to 5 (lowest), default 3")
      field(:depends_on, {:list, :string}, description: "list of work item IDs to depend on")
    end

    @impl true
    def execute(%{id: id, title: title} = params, frame) do
      opts =
        params
        |> Map.drop([:id, :title])
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Enum.map(fn
          {:type, v} -> {:type, String.to_existing_atom(v)}
          {:depends_on, ids} -> {:depends_on, Enum.map(ids, &String.to_atom/1)}
          pair -> pair
        end)

      AgentWorkshop.Workshop.work(String.to_atom(id), title, opts)
      {:reply, Response.text(Response.tool(), "Work item #{id} added."), frame}
    end
  end

  defmodule AgentWorkshop.MCP.Tools.Board do
    @moduledoc false
    use Anubis.Server.Component, type: :tool
    alias Anubis.Server.Response

    schema do
      field(:status, :string,
        description: "filter by status: new, ready, claimed, in_progress, done, failed, blocked"
      )

      field(:type, :string, description: "filter by type: code, review, test, docs")
    end

    @impl true
    def execute(params, frame) do
      filters =
        params
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Enum.map(fn {k, v} -> {k, String.to_existing_atom(v)} end)

      text = format_board(AgentWorkshop.Work.list(filters))
      {:reply, Response.text(Response.tool(), text), frame}
    end

    defp format_board([]), do: "Board is empty."

    defp format_board(items) do
      Enum.map_join(items, "\n", fn item ->
        claimed = if item.claimed_by, do: " (#{item.claimed_by})", else: ""
        deps = if item.depends_on != [], do: " deps:#{inspect(item.depends_on)}", else: ""
        "[#{item.status}] #{item.id} - #{item.title} [#{item.type}]#{claimed}#{deps}"
      end)
    end
  end

  defmodule AgentWorkshop.MCP.Tools.ClaimWork do
    @moduledoc false
    use Anubis.Server.Component, type: :tool
    alias Anubis.Server.Response

    schema do
      field(:id, :string, required: true, description: "work item ID to claim")
      field(:agent, :string, required: true, description: "agent name claiming the work")
    end

    @impl true
    def execute(%{id: id, agent: agent}, frame) do
      case AgentWorkshop.Work.claim(String.to_existing_atom(id), String.to_existing_atom(agent)) do
        :ok -> {:reply, Response.text(Response.tool(), "#{agent} claimed #{id}."), frame}
        {:error, reason} -> {:reply, Response.error(Response.tool(), inspect(reason)), frame}
      end
    end
  end

  defmodule AgentWorkshop.MCP.Tools.CompleteWork do
    @moduledoc false
    use Anubis.Server.Component, type: :tool
    alias Anubis.Server.Response

    schema do
      field(:id, :string, required: true, description: "work item ID to complete")
      field(:result, :string, description: "result summary")
    end

    @impl true
    def execute(%{id: id} = params, frame) do
      result = Map.get(params, :result)

      case AgentWorkshop.Work.complete(String.to_existing_atom(id), result) do
        :ok -> {:reply, Response.text(Response.tool(), "#{id} completed."), frame}
        {:error, reason} -> {:reply, Response.error(Response.tool(), inspect(reason)), frame}
      end
    end
  end

  defmodule AgentWorkshop.MCP.Tools.FailWork do
    @moduledoc false
    use Anubis.Server.Component, type: :tool
    alias Anubis.Server.Response

    schema do
      field(:id, :string, required: true, description: "work item ID that failed")
      field(:error, :string, description: "error description")
    end

    @impl true
    def execute(%{id: id} = params, frame) do
      error = Map.get(params, :error)

      case AgentWorkshop.Work.fail(String.to_existing_atom(id), error) do
        :ok -> {:reply, Response.text(Response.tool(), "#{id} marked as failed."), frame}
        {:error, reason} -> {:reply, Response.error(Response.tool(), inspect(reason)), frame}
      end
    end
  end
end
