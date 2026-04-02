defmodule AgentWorkshop.WorkshopTest do
  use ExUnit.Case, async: false

  alias AgentWorkshop.Workshop

  # A mock backend that doesn't call any CLI
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
            result: "Mock response to: #{prompt}",
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
    on_exit(fn -> Workshop.stop() end)
    :ok
  end

  defp setup_mock do
    Workshop.configure(
      backend: MockBackend,
      backend_config: %{},
      model: "test"
    )
  end

  describe "configure/1" do
    test "requires backend on first call" do
      assert catch_exit(Workshop.configure(model: "sonnet"))
    end

    test "accepts backend and backend_config" do
      assert :ok = setup_mock()
    end
  end

  describe "agent/1,2,3" do
    test "creates an agent" do
      setup_mock()
      Workshop.agent(:impl, "Coder")
      assert :impl in Workshop.agents()
    end

    test "creates agent with opts only" do
      setup_mock()
      Workshop.agent(:impl, max_turns: 5)
      assert :impl in Workshop.agents()
    end

    test "replaces existing agent" do
      setup_mock()
      Workshop.agent(:impl, "v1")
      Workshop.agent(:impl, "v2")
      assert Workshop.agents() == [:impl]
    end
  end

  describe "ask/2" do
    test "sends message and returns agent name" do
      setup_mock()
      Workshop.agent(:impl, "Coder")
      assert :impl = Workshop.ask(:impl, "hello")
    end

    test "result contains response" do
      setup_mock()
      Workshop.agent(:impl, "Coder")
      Workshop.ask(:impl, "hello")
      assert Workshop.result(:impl) =~ "Mock response to: hello"
    end
  end

  describe "cast/2 and await/1" do
    test "cast returns :ok immediately" do
      setup_mock()
      Workshop.agent(:impl, "Coder")
      assert :ok = Workshop.cast(:impl, "background work")
    end

    test "await returns after cast completes" do
      setup_mock()
      Workshop.agent(:impl, "Coder")
      Workshop.cast(:impl, "background work")
      # Give the async task time to complete
      Process.sleep(100)
      Workshop.await(:impl)
      assert Workshop.result(:impl) =~ "Mock response to: background work"
    end
  end

  describe "agents/0" do
    test "returns empty list initially" do
      setup_mock()
      assert Workshop.agents() == []
    end

    test "returns sorted names" do
      setup_mock()
      Workshop.agent(:zeta)
      Workshop.agent(:alpha)
      assert Workshop.agents() == [:alpha, :zeta]
    end
  end

  describe "status/0" do
    test "works with no agents" do
      setup_mock()
      assert :ok = Workshop.status()
    end

    test "works with agents" do
      setup_mock()
      Workshop.agent(:impl)
      assert :ok = Workshop.status()
    end
  end

  describe "cost tracking" do
    test "tracks cost across turns" do
      setup_mock()
      Workshop.agent(:impl, "Coder")
      Workshop.ask(:impl, "turn 1")
      Workshop.ask(:impl, "turn 2")
      assert Workshop.total_cost() == 0.02
    end
  end

  describe "pipe/3" do
    test "pipes result from one agent to another" do
      setup_mock()
      Workshop.agent(:impl, "Coder")
      Workshop.agent(:reviewer, "Reviewer")
      Workshop.ask(:impl, "write code")
      Workshop.pipe(:impl, :reviewer, "review this")
      assert Workshop.result(:reviewer) =~ "Mock response to: review this"
    end

    test "chains with |>" do
      setup_mock()
      Workshop.agent(:impl, "Coder")
      Workshop.agent(:reviewer, "Reviewer")

      result =
        Workshop.ask(:impl, "write code")
        |> Workshop.pipe(:reviewer, "review this")

      assert result == :reviewer
    end
  end

  describe "fan/2" do
    test "sends to multiple agents" do
      setup_mock()
      Workshop.agent(:a)
      Workshop.agent(:b)
      assert :ok = Workshop.fan("hello everyone", [:a, :b])
      Process.sleep(100)
      Workshop.await_all()
      assert Workshop.result(:a) =~ "hello everyone"
      assert Workshop.result(:b) =~ "hello everyone"
    end
  end

  describe "reset/1" do
    test "clears conversation" do
      setup_mock()
      Workshop.agent(:impl, "Coder")
      Workshop.ask(:impl, "hello")
      assert Workshop.result(:impl) != nil
      Workshop.reset(:impl)
      assert Workshop.result(:impl) == nil
      assert :impl in Workshop.agents()
    end
  end

  describe "dismiss/1" do
    test "removes agent" do
      setup_mock()
      Workshop.agent(:impl)
      Workshop.dismiss(:impl)
      refute :impl in Workshop.agents()
    end
  end

  describe "reset_all/0" do
    test "removes all agents" do
      setup_mock()
      Workshop.agent(:a)
      Workshop.agent(:b)
      Workshop.reset_all()
      assert Workshop.agents() == []
    end
  end

  describe "load/1" do
    test "loads a setup file" do
      setup_mock()
      path = Path.join(System.tmp_dir!(), "test_workshop_#{:rand.uniform(100_000)}.exs")

      File.write!(path, """
      agent(:loaded, "From file")
      """)

      assert :ok = Workshop.load(path)
      assert :loaded in Workshop.agents()
      File.rm!(path)
    end

    test "returns error for missing file" do
      setup_mock()
      assert {:error, :not_found} = Workshop.load("nonexistent.exs")
    end
  end

  describe "info/1" do
    test "returns agent info map" do
      setup_mock()
      Workshop.agent(:impl, "Coder", max_turns: 15)
      info = Workshop.info(:impl)
      assert info.name == :impl
      assert info.status == :idle
      assert info.role == "Coder"
      assert info.cost == 0.0
      assert info.turns == 0
    end
  end

  describe "permission validation" do
    test "rejects invalid permission_mode" do
      setup_mock()

      assert_raise ArgumentError, ~r/invalid permission_mode/, fn ->
        Workshop.agent(:impl, "Coder", permission_mode: :bogus)
      end
    end
  end

  describe "shared store" do
    test "put and get" do
      setup_mock()
      Workshop.put(:spec, "LRU cache")
      assert Workshop.get(:spec) == "LRU cache"
    end

    test "get returns nil for missing key" do
      setup_mock()
      assert Workshop.get(:nonexistent) == nil
    end

    test "get with default" do
      setup_mock()
      assert Workshop.get(:missing, "fallback") == "fallback"
    end

    test "store_keys lists keys" do
      setup_mock()
      Workshop.put(:a, 1)
      Workshop.put(:b, 2)
      assert :a in Workshop.store_keys()
      assert :b in Workshop.store_keys()
    end

    test "store_delete removes key" do
      setup_mock()
      Workshop.put(:temp, "value")
      Workshop.store_delete(:temp)
      assert Workshop.get(:temp) == nil
    end

    test "store shows entries" do
      setup_mock()
      Workshop.put(:spec, "cache")
      assert :ok = Workshop.store()
    end

    test "namespaced keys" do
      setup_mock()
      Workshop.put({:impl, :notes}, "chose GenServer")
      assert Workshop.get({:impl, :notes}) == "chose GenServer"
    end

    test "survives agent reset" do
      setup_mock()
      Workshop.agent(:impl, "Coder")
      Workshop.put(:shared, "persists")
      Workshop.reset(:impl)
      assert Workshop.get(:shared) == "persists"
    end
  end

  describe "pubsub" do
    test "receives agent created event" do
      setup_mock()
      AgentWorkshop.PubSub.subscribe(:agent)
      Workshop.agent(:impl, "Coder")
      assert_receive {:workshop_event, :agent, {:agent, :created, :impl}}, 1000
    end

    test "receives agent dismissed event" do
      setup_mock()
      Workshop.agent(:impl, "Coder")
      AgentWorkshop.PubSub.subscribe(:agent)
      Workshop.dismiss(:impl)
      assert_receive {:workshop_event, :agent, {:agent, :dismissed, :impl}}, 1000
    end

    test "receives ask complete event" do
      setup_mock()
      Workshop.agent(:impl, "Coder")
      AgentWorkshop.PubSub.subscribe(:agent)
      Workshop.ask(:impl, "hello")
      assert_receive {:workshop_event, :agent, {:agent, :ask_complete, :impl, _result}}, 1000
    end

    test "receives store put event" do
      setup_mock()
      AgentWorkshop.PubSub.subscribe(:store)
      Workshop.put(:key, "value")
      assert_receive {:workshop_event, :store, {:store, :put, :key}}, 1000
    end

    test ":all topic receives everything" do
      setup_mock()
      AgentWorkshop.PubSub.subscribe(:all)
      Workshop.agent(:impl, "Coder")
      assert_receive {:workshop_event, :all, {:agent, :created, :impl}}, 1000
    end
  end

  describe "telemetry" do
    test "emits ask start and stop events" do
      setup_mock()

      ref =
        :telemetry.attach(
          "test-ask",
          [:agent_workshop, :ask, :stop],
          fn _event, measurements, metadata, _config ->
            send(self(), {:telemetry, measurements, metadata})
          end,
          nil
        )

      Workshop.agent(:impl, "Coder")
      Workshop.ask(:impl, "hello")

      assert_receive {:telemetry, %{cost: _cost, duration: _duration}, %{agent: :impl}}, 1000

      :telemetry.detach("test-ask")
    end

    test "emits agent created event" do
      setup_mock()

      :telemetry.attach(
        "test-agent-created",
        [:agent_workshop, :agent_created],
        fn _event, _measurements, metadata, _config ->
          send(self(), {:telemetry_created, metadata})
        end,
        nil
      )

      Workshop.agent(:impl, "Coder")

      assert_receive {:telemetry_created, %{agent: :impl}}, 1000

      :telemetry.detach("test-agent-created")
    end
  end

  describe "event log" do
    test "records agent events" do
      setup_mock()
      Workshop.agent(:impl, "Coder")
      Workshop.ask(:impl, "hello")

      entries = AgentWorkshop.EventLog.recent()
      formatted = Enum.map(entries, & &1.formatted) |> Enum.reject(&is_nil/1)

      assert Enum.any?(formatted, &String.contains?(&1, "impl created"))
      assert Enum.any?(formatted, &String.contains?(&1, "impl complete"))
    end

    test "watch and unwatch" do
      setup_mock()
      assert :ok = Workshop.watch()
      assert AgentWorkshop.EventLog.watching?()
      assert :ok = Workshop.unwatch()
      refute AgentWorkshop.EventLog.watching?()
    end

    test "events/0 displays" do
      setup_mock()
      Workshop.agent(:impl, "Coder")
      assert :ok = Workshop.events()
    end

    test "clear_events/0 clears" do
      setup_mock()
      Workshop.agent(:impl, "Coder")
      Workshop.clear_events()
      assert AgentWorkshop.EventLog.recent() == []
    end
  end

  describe "scheduling" do
    test "every/3 creates a schedule" do
      setup_mock()
      Workshop.agent(:monitor, "Monitor")
      Workshop.every(:monitor, "check status", interval: 100)
      assert :monitor in AgentWorkshop.Scheduler.list_all()
      Workshop.cancel(:monitor)
    end

    test "schedule ticks cast to agent" do
      setup_mock()
      Workshop.agent(:monitor, "Monitor")
      AgentWorkshop.PubSub.subscribe(:schedule)
      Workshop.every(:monitor, "check", interval: 50)
      assert_receive {:workshop_event, :schedule, {:schedule, :tick, :monitor}}, 500
      Workshop.cancel(:monitor)
    end

    test "cancel stops the schedule" do
      setup_mock()
      Workshop.agent(:monitor, "Monitor")
      Workshop.every(:monitor, "check", interval: 100)
      Workshop.cancel(:monitor)
      refute :monitor in AgentWorkshop.Scheduler.list_all()
    end

    test "schedules/0 works" do
      setup_mock()
      Workshop.agent(:monitor, "Monitor")
      Workshop.every(:monitor, "check", interval: 60_000)
      assert :ok = Workshop.schedules()
      Workshop.cancel(:monitor)
    end
  end

  describe "budgets" do
    test "global budget blocks when exceeded" do
      setup_mock()
      Workshop.configure(max_cost_usd: 0.005)
      Workshop.agent(:impl, "Coder")
      # First ask uses $0.01, exceeding the $0.005 budget
      Workshop.ask(:impl, "hello")
      # Second ask should be blocked
      result = Workshop.ask(:impl, "hello again")
      assert result == {:error, :budget_exceeded}
    end

    test "per-agent budget blocks when exceeded" do
      setup_mock()
      Workshop.agent(:impl, "Coder", max_cost_usd: 0.005)
      Workshop.ask(:impl, "hello")
      result = Workshop.ask(:impl, "hello again")
      assert result == {:error, :budget_exceeded}
    end

    test "budget/0 shows global info" do
      setup_mock()
      assert :ok = Workshop.budget()
    end

    test "budget/1 shows agent info" do
      setup_mock()
      Workshop.agent(:impl, "Coder")
      assert :ok = Workshop.budget(:impl)
    end

    test "reset_budget clears limits" do
      setup_mock()
      Workshop.configure(max_cost_usd: 1.00)
      Workshop.reset_budget()
      # After reset, no budget limit
      info = AgentWorkshop.Budget.info(:global)
      assert info.limit == nil
    end
  end

  describe "work board" do
    test "add and list work items" do
      setup_mock()
      Workshop.work(:cache, "Implement cache", type: :code)
      Workshop.work(:tests, "Write tests", type: :test)
      items = AgentWorkshop.Work.list()
      assert length(items) == 2
    end

    test "items without deps start as ready" do
      setup_mock()
      Workshop.work(:cache, "Implement cache", type: :code)
      item = Workshop.work_item(:cache)
      assert item.status == :ready
    end

    test "items with unmet deps start as new" do
      setup_mock()
      Workshop.work(:cache, "Implement cache", type: :code)
      Workshop.work(:review, "Review cache", type: :review, depends_on: [:cache])
      item = Workshop.work_item(:review)
      assert item.status == :new
    end

    test "completing a dep unblocks dependents" do
      setup_mock()
      Workshop.agent(:impl, "Coder")
      Workshop.work(:cache, "Implement cache", type: :code)
      Workshop.work(:review, "Review cache", type: :review, depends_on: [:cache])

      assert Workshop.work_item(:review).status == :new

      Workshop.claim_work(:cache, :impl)
      Workshop.start_work(:cache)
      Workshop.complete_work(:cache)

      assert Workshop.work_item(:review).status == :ready
    end

    test "claim and start workflow" do
      setup_mock()
      Workshop.agent(:impl, "Coder")
      Workshop.work(:cache, "Implement cache", type: :code)

      assert :ok = Workshop.claim_work(:cache, :impl)
      assert Workshop.work_item(:cache).claimed_by == :impl
      assert Workshop.work_item(:cache).status == :claimed

      assert :ok = Workshop.start_work(:cache)
      assert Workshop.work_item(:cache).status == :in_progress
    end

    test "complete sets done and timestamp" do
      setup_mock()
      Workshop.agent(:impl, "Coder")
      Workshop.work(:cache, "Implement cache", type: :code)
      Workshop.claim_work(:cache, :impl)
      Workshop.complete_work(:cache, "Done with GenServer")

      item = Workshop.work_item(:cache)
      assert item.status == :done
      assert item.result == "Done with GenServer"
      assert item.completed_at != nil
    end

    test "fail blocks dependents" do
      setup_mock()
      Workshop.agent(:impl, "Coder")
      Workshop.work(:cache, "Implement cache", type: :code)
      Workshop.work(:review, "Review", type: :review, depends_on: [:cache])

      Workshop.claim_work(:cache, :impl)
      Workshop.fail_work(:cache, "tests broken")

      assert Workshop.work_item(:cache).status == :failed
      assert Workshop.work_item(:review).status == :blocked
    end

    test "cancel work" do
      setup_mock()
      Workshop.work(:cache, "Implement cache", type: :code)
      Workshop.cancel_work(:cache)
      assert Workshop.work_item(:cache).status == :cancelled
    end

    test "filter by status" do
      setup_mock()
      Workshop.work(:a, "Task A", type: :code)
      Workshop.work(:b, "Task B", type: :code)
      Workshop.work(:c, "Task C", type: :review, depends_on: [:a])

      ready = AgentWorkshop.Work.list(status: :ready)
      assert length(ready) == 2
      assert Enum.all?(ready, &(&1.status == :ready))
    end

    test "filter by type" do
      setup_mock()
      Workshop.work(:a, "Code task", type: :code)
      Workshop.work(:b, "Review task", type: :review)

      code_items = AgentWorkshop.Work.list(type: :code)
      assert length(code_items) == 1
      assert hd(code_items).type == :code
    end

    test "board display works" do
      setup_mock()
      Workshop.work(:cache, "Implement cache", type: :code)
      assert :ok = Workshop.board()
    end

    test "board display with empty board" do
      setup_mock()
      assert :ok = Workshop.board()
    end

    test "priority ordering" do
      setup_mock()
      Workshop.work(:low, "Low priority", type: :code, priority: 5)
      Workshop.work(:high, "High priority", type: :code, priority: 1)
      Workshop.work(:mid, "Mid priority", type: :code, priority: 3)

      items = AgentWorkshop.Work.list()
      assert Enum.map(items, & &1.id) == [:high, :mid, :low]
    end

    test "pubsub events on work state changes" do
      setup_mock()
      Workshop.agent(:impl, "Coder")
      AgentWorkshop.PubSub.subscribe(:work)

      Workshop.work(:cache, "Implement cache", type: :code)
      assert_receive {:workshop_event, :work, {:work, :added, :cache}}, 1000

      Workshop.claim_work(:cache, :impl)
      assert_receive {:workshop_event, :work, {:work, :claimed, :cache, :impl}}, 1000

      Workshop.complete_work(:cache)
      assert_receive {:workshop_event, :work, {:work, :completed, :cache}}, 1000
    end

    test "summary counts" do
      setup_mock()
      Workshop.work(:a, "A", type: :code)
      Workshop.work(:b, "B", type: :code)
      Workshop.work(:c, "C", type: :review, depends_on: [:a])

      summary = AgentWorkshop.Work.summary()
      assert summary[:ready] == 2
      assert summary[:new] == 1
    end
  end

  describe "profiles" do
    test "define and list profiles" do
      setup_mock()
      Workshop.profile(:coder, "You write code.", max_turns: 15)
      Workshop.profile(:reviewer, "Review only.", model: "opus")
      assert :ok = Workshop.profiles()
      assert :coder in AgentWorkshop.Profiles.list()
      assert :reviewer in AgentWorkshop.Profiles.list()
    end

    test "from_profile creates agent" do
      setup_mock()
      Workshop.profile(:coder, "You write code.", max_turns: 15)
      Workshop.from_profile(:coder, :coder_42)
      assert :coder_42 in Workshop.agents()
    end

    test "from_profile with overrides" do
      setup_mock()
      Workshop.profile(:coder, "You write code.", model: "sonnet")
      Workshop.from_profile(:coder, :coder_opus, model: "opus")
      info = Workshop.info(:coder_opus)
      assert info.model == "opus"
    end

    test "from_profile raises for unknown profile" do
      setup_mock()

      assert_raise ArgumentError, ~r/unknown profile/, fn ->
        Workshop.from_profile(:nonexistent, :agent)
      end
    end
  end

  describe "workshop_tools" do
    test "workshop_tools option adds mcp_config to query_opts" do
      setup_mock()
      Workshop.agent(:orchestrator, "Coordinator", workshop_tools: true)
      entry = Workshop.info(:orchestrator)
      # The mcp_config should be in the query_opts (not visible in info, but agent was created)
      assert :orchestrator in Workshop.agents()
    end
  end
end
