defmodule AgentWorkshop.WorkflowTest do
  use ExUnit.Case, async: false

  alias AgentWorkshop.{Work, Workflow, Workshop}

  setup do
    Workshop.stop()
    on_exit(fn -> Workshop.stop() end)
    :ok
  end

  describe "define/2" do
    test "stores a workflow with parsed stages" do
      assert :ok =
               Workflow.define(:feature, [
                 {:plan, :planner, "Plan the feature"},
                 {:implement, :coder, "Implement it", from: :plan},
                 {:test, :tester, "Test it", from: :implement}
               ])

      wf = Workflow.get(:feature)
      assert wf.name == :feature
      assert wf.status == :defined
      assert length(wf.stages) == 3

      [plan, impl, test_stage] = wf.stages
      assert plan.work_id == :feature_plan
      assert plan.depends_on == []
      assert impl.work_id == :feature_implement
      assert impl.depends_on == [:feature_plan]
      assert impl.from_stages == [:feature_plan]
      assert test_stage.depends_on == [:feature_implement]
    end

    test "handles fan-in dependencies" do
      Workflow.define(:review, [
        {:code, :coder, "Write code"},
        {:test, :tester, "Write tests"},
        {:review, :reviewer, "Review everything", from: [:code, :test]}
      ])

      wf = Workflow.get(:review)
      review_stage = List.last(wf.stages)
      assert review_stage.depends_on == [:review_code, :review_test]
      assert review_stage.from_stages == [:review_code, :review_test]
    end

    test "handles file input" do
      Workflow.define(:docs, [
        {:write, :writer, "Write docs", from: "README.md"}
      ])

      wf = Workflow.get(:docs)
      [stage] = wf.stages
      assert stage.file_input == "README.md"
      assert stage.depends_on == []
    end

    test "accepts type and priority options" do
      Workflow.define(:typed, [
        {:impl, :coder, "Implement", type: :code, priority: 1}
      ])

      wf = Workflow.get(:typed)
      [stage] = wf.stages
      assert stage.type == :code
      assert stage.priority == 1
    end

    test "rejects invalid stage tuples" do
      assert {:error, {:invalid_stage, :bad}} = Workflow.define(:bad, [:bad])
    end
  end

  describe "run/1" do
    test "expands stages into work items" do
      Workflow.define(:pipeline, [
        {:first, :agent_a, "First step"},
        {:second, :agent_b, "Second step", from: :first}
      ])

      assert :ok = Workflow.run(:pipeline)

      first = Work.get(:pipeline_first)
      assert first != nil
      assert first.title == "First step"
      assert first.status == :ready
      assert first.metadata.workflow == :pipeline

      second = Work.get(:pipeline_second)
      assert second != nil
      assert second.depends_on == [:pipeline_first]
      assert second.status == :new
      assert second.metadata.from_stages == [:pipeline_first]
    end

    test "reads file input into spec" do
      path = Path.join(System.tmp_dir!(), "workflow_test_input.md")
      File.write!(path, "Feature spec content")
      on_exit(fn -> File.rm(path) end)

      Workflow.define(:file_wf, [
        {:plan, :planner, "Plan from spec", from: path}
      ])

      Workflow.run(:file_wf)

      item = Work.get(:file_wf_plan)
      assert item.spec == "Feature spec content"
    end

    test "errors if workflow not found" do
      assert {:error, :not_found} = Workflow.run(:nonexistent)
    end

    test "errors if already running" do
      Workflow.define(:running, [{:step, :agent, "Do thing"}])
      Workflow.run(:running)
      assert {:error, :already_running} = Workflow.run(:running)
    end

    test "updates status to running" do
      Workflow.define(:status_test, [{:step, :agent, "Do thing"}])
      Workflow.run(:status_test)
      assert Workflow.get(:status_test).status == :running
    end
  end

  describe "reset/1" do
    test "removes work items and resets status" do
      Workflow.define(:resettable, [
        {:a, :agent, "Step A"},
        {:b, :agent, "Step B", from: :a}
      ])

      Workflow.run(:resettable)
      assert Work.get(:resettable_a) != nil

      assert :ok = Workflow.reset(:resettable)
      assert Work.get(:resettable_a) == nil
      assert Work.get(:resettable_b) == nil
      assert Workflow.get(:resettable).status == :defined
    end

    test "allows re-running after reset" do
      Workflow.define(:rerun, [{:step, :agent, "Do thing"}])
      Workflow.run(:rerun)
      Workflow.reset(:rerun)
      assert :ok = Workflow.run(:rerun)
      assert Workflow.get(:rerun).status == :running
    end
  end

  describe "status/1" do
    test "returns workflow and work items" do
      Workflow.define(:st, [
        {:a, :agent, "Step A"},
        {:b, :agent, "Step B", from: :a}
      ])

      Workflow.run(:st)

      {wf, items} = Workflow.status(:st)
      assert wf.name == :st
      assert length(items) == 2
      assert Enum.all?(items, &(!is_nil(&1)))
    end

    test "errors for unknown workflow" do
      assert {:error, :not_found} = Workflow.status(:nope)
    end
  end

  describe "check_completion/1" do
    test "marks workflow completed when all stages done" do
      Workflow.define(:complete, [
        {:a, :agent, "Step A"},
        {:b, :agent, "Step B"}
      ])

      Workflow.run(:complete)

      # Manually complete both items
      Work.claim(:complete_a, :test_agent)
      Work.complete(:complete_a, "done A")
      Work.claim(:complete_b, :test_agent)
      Work.complete(:complete_b, "done B")

      Workflow.check_completion(:complete)
      assert Workflow.get(:complete).status == :completed
    end

    test "marks workflow failed when a stage fails" do
      Workflow.define(:fail_wf, [
        {:a, :agent, "Step A"},
        {:b, :agent, "Step B", from: :a}
      ])

      Workflow.run(:fail_wf)

      Work.claim(:fail_wf_a, :test_agent)
      Work.fail(:fail_wf_a, "broken")

      Workflow.check_completion(:fail_wf)
      assert Workflow.get(:fail_wf).status == :failed

      # Dependent should be blocked
      assert Work.get(:fail_wf_b).status == :blocked
    end
  end

  describe "workflow_for_item/1" do
    test "finds workflow for a work item" do
      Workflow.define(:lookup, [{:step, :agent, "Do thing"}])
      Workflow.run(:lookup)

      assert Workflow.workflow_for_item(:lookup_step) == :lookup
    end

    test "returns nil for non-workflow items" do
      Work.add(:standalone, "Regular work", type: :code)
      assert Workflow.workflow_for_item(:standalone) == nil
      Work.remove(:standalone)
    end
  end

  describe "list/0" do
    test "lists all workflows" do
      Workflow.define(:wf_a, [{:s, :a, "A"}])
      Workflow.define(:wf_b, [{:s, :a, "B"}])

      wfs = Workflow.list()
      names = Enum.map(wfs, & &1.name)
      assert :wf_a in names
      assert :wf_b in names
    end
  end

  describe "serialization" do
    test "round-trips through to_map/from_map" do
      Workflow.define(:serial, [
        {:plan, :planner, "Plan", from: "spec.md"},
        {:impl, :coder, "Implement", from: :plan, type: :code, priority: 1}
      ])

      wf = Workflow.get(:serial)
      map = Workflow.to_map(wf)
      restored = Workflow.from_map(map)

      assert restored.name == :serial
      assert restored.status == :defined
      assert length(restored.stages) == 2

      [plan, impl] = restored.stages
      assert plan.file_input == "spec.md"
      assert impl.depends_on == [:serial_plan]
      assert impl.type == :code
      assert impl.priority == 1
    end
  end

  describe "build_prompt injection" do
    test "injects dependency results into prompt" do
      Workflow.define(:prompt_test, [
        {:a, :agent, "Step A"},
        {:b, :agent, "Step B", from: :a}
      ])

      Workflow.run(:prompt_test)

      # Complete step A with a result
      Work.claim(:prompt_test_a, :test_agent)
      Work.complete(:prompt_test_a, "Result from step A")

      # Step B should now be ready
      item_b = Work.get(:prompt_test_b)
      assert item_b.status == :ready

      # Test the build_prompt function via the BoardWorker module
      # We can't call the private function directly, but we can verify
      # the metadata is set correctly for the board worker to use
      assert item_b.metadata.from_stages == [:prompt_test_a]
    end
  end
end
