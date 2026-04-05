defmodule AgentWorkshop.MCPToolsTest do
  use ExUnit.Case, async: false

  alias AgentWorkshop.MCP.Tools.{AddWork, Agents, Board, ClaimWork, CompleteWork, Configure}

  alias AgentWorkshop.MCP.Tools.{
    Cost,
    CreateAgent,
    Dismiss,
    FailWork,
    Info,
    Reset,
    Result,
    Status
  }

  alias AgentWorkshop.Workshop
  alias Anubis.Server.Frame

  @moduletag :mcp_tools

  # Reuse the mock backend from the main test
  defmodule MockBackend do
    @behaviour AgentWorkshop.Backend

    @impl true
    def start_session(_config, _opts) do
      {:ok, spawn_link(fn -> mock_loop(%{history: [], session_id: nil}) end)}
    end

    @impl true
    def send_message(server, prompt, _opts) do
      send(server, {:send, self(), prompt})

      receive do
        {:result, result} -> {:ok, result}
      after
        1000 -> {:error, :timeout}
      end
    end

    @impl true
    def session_id(server), do: call(server, :session_id)
    @impl true
    def history(server), do: call(server, :history)
    @impl true
    def total_cost(server), do: call(server, :total_cost)
    @impl true
    def turn_count(server), do: call(server, :turn_count)
    @impl true
    def last_result(server), do: call(server, :last_result)

    @impl true
    def stop_session(server) do
      if Process.alive?(server), do: Process.exit(server, :normal)
      :ok
    end

    defp call(server, msg) do
      send(server, {msg, self()})

      receive do
        {:reply, val} -> val
      after
        1000 -> nil
      end
    end

    defp mock_loop(state) do
      receive do
        {:send, from, prompt} ->
          result = %{
            result: "Mock: #{prompt}",
            session_id: "mock-session",
            cost_usd: 0.01,
            is_error: false,
            duration_ms: 100,
            num_turns: length(state.history) + 1
          }

          send(from, {:result, result})
          mock_loop(%{state | history: state.history ++ [result], session_id: "mock-session"})

        {:session_id, from} ->
          send(from, {:reply, state.session_id})
          mock_loop(state)

        {:history, from} ->
          send(from, {:reply, state.history})
          mock_loop(state)

        {:total_cost, from} ->
          total = Enum.reduce(state.history, 0.0, fn r, acc -> acc + (r.cost_usd || 0.0) end)
          send(from, {:reply, total})
          mock_loop(state)

        {:turn_count, from} ->
          send(from, {:reply, length(state.history)})
          mock_loop(state)

        {:last_result, from} ->
          send(from, {:reply, List.last(state.history)})
          mock_loop(state)
      end
    end
  end

  setup do
    Workshop.stop()

    Workshop.configure(
      backend: MockBackend,
      backend_config: %{},
      model: "test"
    )

    on_exit(fn -> Workshop.stop() end)
    {:ok, frame: %Frame{}}
  end

  describe "Agent tools" do
    test "Agents returns empty when no agents", %{frame: frame} do
      {:reply, response, _} = Agents.execute(%{}, frame)
      assert response_text(response) == "No agents."
    end

    test "CreateAgent creates an agent", %{frame: frame} do
      {:reply, response, _} =
        CreateAgent.execute(%{name: "impl", role: "Coder"}, frame)

      assert response_text(response) =~ "impl created"
      assert :impl in Workshop.agents()
    end

    test "Agents lists created agents", %{frame: frame} do
      Workshop.agent(:alpha)
      Workshop.agent(:beta)
      {:reply, response, _} = Agents.execute(%{}, frame)
      text = response_text(response)
      assert text =~ "alpha"
      assert text =~ "beta"
    end

    test "Dismiss removes an agent", %{frame: frame} do
      Workshop.agent(:temp)

      {:reply, response, _} =
        Dismiss.execute(%{agent: "temp"}, frame)

      assert response_text(response) =~ "dismissed"
      refute :temp in Workshop.agents()
    end

    test "Reset resets an agent", %{frame: frame} do
      Workshop.agent(:impl, "Coder")
      Workshop.ask(:impl, "hello")
      assert Workshop.result(:impl) != nil

      {:reply, response, _} =
        Reset.execute(%{agent: "impl"}, frame)

      assert response_text(response) =~ "reset"
      assert Workshop.result(:impl) == nil
    end
  end

  describe "Board tools" do
    test "Board returns empty board", %{frame: frame} do
      {:reply, response, _} = Board.execute(%{}, frame)
      assert response_text(response) == "Board is empty."
    end

    test "AddWork adds an item", %{frame: frame} do
      {:reply, response, _} =
        AddWork.execute(
          %{id: "cache", title: "Implement cache", type: "code", spec: "LRU cache"},
          frame
        )

      assert response_text(response) =~ "cache added"
      assert AgentWorkshop.Work.get(:cache) != nil
    end

    test "Board lists items after adding", %{frame: frame} do
      Workshop.work(:task_a, "Task A", type: :code)
      Workshop.work(:task_b, "Task B", type: :review)

      {:reply, response, _} = Board.execute(%{}, frame)
      text = response_text(response)
      assert text =~ "task_a"
      assert text =~ "task_b"
    end

    test "Board filters by status", %{frame: frame} do
      Workshop.work(:ready_one, "Ready", type: :code)
      Workshop.work(:blocked_one, "Blocked", type: :review, depends_on: [:ready_one])

      {:reply, response, _} =
        Board.execute(%{status: "ready"}, frame)

      text = response_text(response)
      assert text =~ "ready_one"
      refute text =~ "blocked_one"
    end

    test "ClaimWork claims an item", %{frame: frame} do
      Workshop.agent(:impl)
      Workshop.work(:claim_test, "Claim me", type: :code)

      {:reply, response, _} =
        ClaimWork.execute(%{id: "claim_test", agent: "impl"}, frame)

      assert response_text(response) =~ "claimed"
      assert AgentWorkshop.Work.get(:claim_test).status == :claimed
    end

    test "CompleteWork completes an item", %{frame: frame} do
      Workshop.agent(:impl)
      Workshop.work(:comp_test, "Complete me", type: :code)
      Workshop.claim_work(:comp_test, :impl)

      {:reply, response, _} =
        CompleteWork.execute(
          %{id: "comp_test", result: "All done"},
          frame
        )

      assert response_text(response) =~ "completed"
      assert AgentWorkshop.Work.get(:comp_test).status == :done
    end

    test "FailWork fails an item", %{frame: frame} do
      Workshop.agent(:impl)
      Workshop.work(:fail_test, "Fail me", type: :code)
      Workshop.claim_work(:fail_test, :impl)

      {:reply, response, _} =
        FailWork.execute(
          %{id: "fail_test", error: "tests broken"},
          frame
        )

      assert response_text(response) =~ "failed"
      assert AgentWorkshop.Work.get(:fail_test).status == :failed
    end
  end

  describe "Observability tools" do
    test "Status with no agents", %{frame: frame} do
      {:reply, response, _} = Status.execute(%{}, frame)
      assert response_text(response) == "No agents."
    end

    test "Status with agents", %{frame: frame} do
      Workshop.agent(:impl, "Coder")
      {:reply, response, _} = Status.execute(%{}, frame)
      text = response_text(response)
      assert text =~ "impl"
      assert text =~ "idle"
    end

    test "Result returns agent result", %{frame: frame} do
      Workshop.agent(:impl, "Coder")
      Workshop.ask(:impl, "hello")

      {:reply, response, _} =
        Result.execute(%{agent: "impl"}, frame)

      assert response_text(response) =~ "Mock: hello"
    end

    test "Result returns no result for fresh agent", %{frame: frame} do
      Workshop.agent(:impl)

      {:reply, response, _} =
        Result.execute(%{agent: "impl"}, frame)

      assert response_text(response) == "(no result)"
    end

    test "Cost with no agents", %{frame: frame} do
      {:reply, response, _} = Cost.execute(%{}, frame)
      assert response_text(response) == "No agents."
    end

    test "Cost tracks agent spend", %{frame: frame} do
      Workshop.agent(:impl, "Coder")
      Workshop.ask(:impl, "hello")

      {:reply, response, _} = Cost.execute(%{}, frame)
      text = response_text(response)
      assert text =~ "impl"
      assert text =~ "Total:"
    end

    test "Info returns agent details", %{frame: frame} do
      Workshop.agent(:impl, "Coder", max_turns: 15)

      {:reply, response, _} =
        Info.execute(%{agent: "impl"}, frame)

      # Info returns JSON response, not text
      assert {:ok, _} = Jason.decode(response_text(response))
    end
  end

  describe "Configure tool" do
    test "Configure sets options", %{frame: frame} do
      {:reply, response, _} =
        Configure.execute(%{model: "opus"}, frame)

      assert response_text(response) == "Configured."
    end
  end

  # Extract text from Anubis response (string-keyed maps)
  defp response_text(%{content: [%{"text" => text} | _]}), do: text
  defp response_text(%{content: [%{text: text} | _]}), do: text
  defp response_text(other), do: inspect(other)
end
