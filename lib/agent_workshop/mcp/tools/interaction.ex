if Code.ensure_loaded?(Anubis.Server) do
  defmodule AgentWorkshop.MCP.Tools.Ask do
    @moduledoc false
    use Anubis.Server.Component, type: :tool
    alias Anubis.Server.Response

    schema do
      field(:agent, :string, required: true, description: "agent name")
      field(:prompt, :string, required: true, description: "message to send")
    end

    @impl true
    def execute(%{agent: name, prompt: prompt}, frame) do
      atom_name = String.to_existing_atom(name)

      case AgentWorkshop.Workshop.ask(atom_name, prompt) do
        {:error, reason} ->
          {:reply, Response.error(Response.tool(), inspect(reason)), frame}

        _name ->
          text = AgentWorkshop.Workshop.result(atom_name) || "(no response)"
          {:reply, Response.text(Response.tool(), text), frame}
      end
    end
  end

  defmodule AgentWorkshop.MCP.Tools.Cast do
    @moduledoc false
    use Anubis.Server.Component, type: :tool
    alias Anubis.Server.Response

    schema do
      field(:agent, :string, required: true, description: "agent name")
      field(:prompt, :string, required: true, description: "message to send asynchronously")
    end

    @impl true
    def execute(%{agent: name, prompt: prompt}, frame) do
      atom_name = String.to_existing_atom(name)

      case AgentWorkshop.Workshop.cast(atom_name, prompt) do
        :ok ->
          {:reply,
           Response.text(Response.tool(), "Cast to #{name}. Use await to get the result."), frame}

        {:error, reason} ->
          {:reply, Response.error(Response.tool(), inspect(reason)), frame}
      end
    end
  end

  defmodule AgentWorkshop.MCP.Tools.Await do
    @moduledoc false
    use Anubis.Server.Component, type: :tool
    alias Anubis.Server.Response

    @poll_interval 2_000

    schema do
      field(:agent, :string, required: true, description: "agent name to wait for")

      field(:timeout, :integer,
        description: "max milliseconds to wait (default: 120000). 0 to just check status."
      )
    end

    @impl true
    def execute(%{agent: name} = params, frame) do
      atom_name = String.to_existing_atom(name)
      timeout = Map.get(params, :timeout, 120_000)

      if timeout == 0 do
        check_status(atom_name, name, frame)
      else
        poll_until_idle(atom_name, name, timeout, frame)
      end
    end

    defp check_status(atom_name, name, frame) do
      info = AgentWorkshop.Workshop.info(atom_name)

      if info.status == :idle do
        text = AgentWorkshop.Workshop.result(atom_name) || "(no result yet)"
        {:reply, Response.text(Response.tool(), text), frame}
      else
        {:reply,
         Response.text(
           Response.tool(),
           "#{name} is still working. Call await again later, or use status to check."
         ), frame}
      end
    end

    defp poll_until_idle(atom_name, name, timeout, frame) do
      deadline = System.monotonic_time(:millisecond) + timeout
      do_poll(atom_name, name, deadline, frame)
    end

    defp do_poll(atom_name, name, deadline, frame) do
      info = AgentWorkshop.Workshop.info(atom_name)

      cond do
        info.status == :idle ->
          text = AgentWorkshop.Workshop.result(atom_name) || "(no result)"
          {:reply, Response.text(Response.tool(), text), frame}

        System.monotonic_time(:millisecond) >= deadline ->
          {:reply, Response.text(Response.tool(), "#{name} timed out (still working)."), frame}

        true ->
          Process.sleep(@poll_interval)
          do_poll(atom_name, name, deadline, frame)
      end
    end
  end

  defmodule AgentWorkshop.MCP.Tools.AwaitAll do
    @moduledoc false
    use Anubis.Server.Component, type: :tool
    alias Anubis.Server.Response

    @poll_interval 2_000

    schema do
      field(:timeout, :integer,
        description: "max milliseconds to wait (default: 120000). 0 to just check."
      )
    end

    @impl true
    def execute(params, frame) do
      timeout = Map.get(params, :timeout, 120_000)

      if timeout > 0 do
        deadline = System.monotonic_time(:millisecond) + timeout
        poll_all_idle(deadline)
      end

      results = collect_results(AgentWorkshop.Workshop.agents())
      {:reply, Response.text(Response.tool(), results), frame}
    end

    defp poll_all_idle(deadline) do
      agents = AgentWorkshop.Workshop.agents()

      any_busy? =
        Enum.any?(agents, fn name ->
          AgentWorkshop.Workshop.info(name).status == :working
        end)

      if any_busy? and System.monotonic_time(:millisecond) < deadline do
        Process.sleep(@poll_interval)
        poll_all_idle(deadline)
      end
    end

    defp collect_results(agents) do
      Enum.map_join(agents, "\n\n", fn name ->
        info = AgentWorkshop.Workshop.info(name)
        status = if info.status == :working, do: " (still working)", else: ""
        text = AgentWorkshop.Workshop.result(name)
        "## #{name}#{status}\n#{text || "(no result yet)"}"
      end)
    end
  end

  defmodule AgentWorkshop.MCP.Tools.Pipe do
    @moduledoc false
    use Anubis.Server.Component, type: :tool
    alias Anubis.Server.Response

    schema do
      field(:from, :string, required: true, description: "source agent name")
      field(:to, :string, required: true, description: "target agent name")
      field(:message, :string, description: "framing message for what the target should do")
    end

    @impl true
    def execute(%{from: from, to: to} = params, frame) do
      from_atom = String.to_existing_atom(from)
      to_atom = String.to_existing_atom(to)
      message = Map.get(params, :message)

      case AgentWorkshop.Workshop.pipe(from_atom, to_atom, message) do
        {:error, reason} ->
          {:reply, Response.error(Response.tool(), inspect(reason)), frame}

        _name ->
          text = AgentWorkshop.Workshop.result(to_atom) || "(no result)"
          {:reply, Response.text(Response.tool(), text), frame}
      end
    end
  end

  defmodule AgentWorkshop.MCP.Tools.Fan do
    @moduledoc false
    use Anubis.Server.Component, type: :tool
    alias Anubis.Server.Response

    schema do
      field(:message, :string, required: true, description: "message to send to all agents")
      field(:agents, {:list, :string}, required: true, description: "list of agent names")
    end

    @impl true
    def execute(%{message: message, agents: agents}, frame) do
      atom_names = Enum.map(agents, &String.to_existing_atom/1)
      AgentWorkshop.Workshop.fan(message, atom_names)
      names = Enum.join(agents, ", ")

      {:reply, Response.text(Response.tool(), "Sent to #{names}. Use await_all to collect."),
       frame}
    end
  end
end
