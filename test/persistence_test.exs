defmodule AgentWorkshop.PersistenceTest do
  use ExUnit.Case, async: false

  alias AgentWorkshop.{Persistence, Store, Work}

  @test_dir Path.join(System.tmp_dir!(), "agent_workshop_test_#{:rand.uniform(100_000)}")

  setup do
    File.rm_rf!(@test_dir)
    AgentWorkshop.Workshop.stop()

    on_exit(fn ->
      Persistence.disable()
      AgentWorkshop.Workshop.stop()
      File.rm_rf!(@test_dir)
    end)

    :ok
  end

  describe "enable/disable" do
    test "starts disabled" do
      refute Persistence.enabled?()
    end

    test "enable creates directory" do
      Persistence.enable(@test_dir)
      assert File.dir?(@test_dir)
      assert Persistence.enabled?()
    end

    test "enable with true uses default dir" do
      # Just test the call doesn't crash -- cleanup will handle the dir
      Persistence.enable(true)
      assert Persistence.enabled?()
      Persistence.disable()
      File.rm_rf!(".agent_workshop")
    end

    test "disable stops persistence" do
      Persistence.enable(@test_dir)
      Persistence.disable()
      refute Persistence.enabled?()
    end
  end

  describe "work board persistence" do
    test "saves work items to disk" do
      Persistence.enable(@test_dir)
      Work.add(:cache, "Implement cache", type: :code, priority: 1)
      Work.add(:tests, "Write tests", type: :test, depends_on: [:cache])
      Persistence.flush()

      path = Path.join(@test_dir, "work.json")
      assert File.exists?(path)

      {:ok, contents} = File.read(path)
      items = Jason.decode!(contents)
      assert length(items) == 2

      ids = Enum.map(items, & &1["id"]) |> Enum.sort()
      assert ids == ["cache", "tests"]
    end

    test "reloads work items on enable" do
      # Write initial state
      File.mkdir_p!(@test_dir)

      items = [
        %{
          "id" => "reload_task",
          "title" => "Reloaded task",
          "spec" => nil,
          "type" => "code",
          "status" => "ready",
          "priority" => 2,
          "depends_on" => [],
          "claimed_by" => nil,
          "result" => nil,
          "error" => nil,
          "created_at" => "2026-04-04T00:00:00Z",
          "completed_at" => nil
        }
      ]

      File.write!(Path.join(@test_dir, "work.json"), Jason.encode!(items))

      # Enable loads from disk
      Persistence.enable(@test_dir)

      item = Work.get(:reload_task)
      assert item != nil
      assert item.title == "Reloaded task"
      assert item.type == :code
      assert item.status == :ready
      assert item.priority == 2
    end

    test "round-trips work item through lifecycle" do
      Persistence.enable(@test_dir)

      Work.add(:rt, "Round trip", type: :code, spec: "Full lifecycle test")
      Work.claim(:rt, :impl)
      Work.start_work(:rt)
      Work.complete(:rt, "All done")
      Persistence.flush()

      # Clear ETS and reload
      Work.clear()
      assert Work.get(:rt) == nil

      Persistence.disable()
      Persistence.enable(@test_dir)

      item = Work.get(:rt)
      assert item.status == :done
      assert item.result == "All done"
      assert item.claimed_by == :impl
      assert item.completed_at != nil
    end
  end

  describe "store persistence" do
    test "saves store entries to disk" do
      Persistence.enable(@test_dir)
      Store.put(:spec, "LRU cache")
      Store.put(:notes, "Use GenServer")
      Persistence.flush()

      path = Path.join(@test_dir, "store.json")
      assert File.exists?(path)

      {:ok, contents} = File.read(path)
      entries = Jason.decode!(contents)
      assert length(entries) == 2
    end

    test "reloads store entries on enable" do
      File.mkdir_p!(@test_dir)

      entries = [
        %{"key" => "__atom__:reloaded", "value" => "from disk"}
      ]

      File.write!(Path.join(@test_dir, "store.json"), Jason.encode!(entries))

      Persistence.enable(@test_dir)

      assert Store.get(:reloaded) == "from disk"
    end

    test "handles namespaced tuple keys" do
      Persistence.enable(@test_dir)
      Store.put({:impl, :notes}, "chose GenServer")
      Persistence.flush()

      # Disable first (flushes pending), then clear ETS directly, then reload
      Persistence.disable()
      :ets.delete_all_objects(Store.table_name())
      Persistence.enable(@test_dir)

      assert Store.get({:impl, :notes}) == "chose GenServer"
    end

    test "handles numeric values" do
      Persistence.enable(@test_dir)
      Store.put(:count, 42)
      Persistence.flush()

      Persistence.disable()
      :ets.delete_all_objects(Store.table_name())
      Persistence.enable(@test_dir)

      assert Store.get(:count) == 42
    end
  end

  describe "event log" do
    test "appends events to jsonl file" do
      Persistence.enable(@test_dir)
      Work.add(:ev_test, "Event test", type: :code)
      # Give PubSub time to deliver
      Process.sleep(50)
      Persistence.flush()

      path = Path.join(@test_dir, "events.jsonl")
      assert File.exists?(path)

      lines =
        File.read!(path)
        |> String.split("\n", trim: true)

      assert lines != []

      first = Jason.decode!(hd(lines))
      assert Map.has_key?(first, "event")
      assert Map.has_key?(first, "timestamp")
    end
  end

  describe "Work serialization" do
    test "to_map and from_map round-trip" do
      now = DateTime.utc_now()

      item = %Work{
        id: :test,
        title: "Test item",
        spec: "Full spec",
        type: :code,
        status: :in_progress,
        priority: 1,
        depends_on: [:dep1, :dep2],
        claimed_by: :worker,
        result: nil,
        error: nil,
        created_at: now,
        completed_at: nil
      }

      map = Work.to_map(item)
      restored = Work.from_map(map)

      assert restored.id == :test
      assert restored.title == "Test item"
      assert restored.spec == "Full spec"
      assert restored.type == :code
      assert restored.status == :in_progress
      assert restored.priority == 1
      assert restored.depends_on == [:dep1, :dep2]
      assert restored.claimed_by == :worker
      assert restored.created_at != nil
    end

    test "to_map produces valid JSON" do
      item = %Work{
        id: :json_test,
        title: "JSON test",
        type: :code,
        status: :ready,
        depends_on: [],
        created_at: DateTime.utc_now()
      }

      map = Work.to_map(item)
      assert {:ok, _} = Jason.encode(map)
    end
  end
end
