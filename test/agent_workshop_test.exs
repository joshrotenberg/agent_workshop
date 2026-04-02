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
end
