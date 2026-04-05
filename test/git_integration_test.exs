defmodule AgentWorkshop.GitIntegrationTest do
  use ExUnit.Case, async: false

  alias AgentWorkshop.Workshop

  @moduletag :git_integration

  setup do
    Workshop.stop()
    on_exit(fn -> Workshop.stop() end)
    :ok
  end

  describe "configure(git_context: true)" do
    test "injects git context into global context" do
      Workshop.configure(
        context: "Test project.",
        git_context: true
      )

      context = :persistent_term.get({AgentWorkshop, :context}, nil)
      assert context =~ "Test project."
      assert context =~ "## Git Context"
      assert context =~ "Branch:"
    end

    test "works without prior context" do
      Workshop.configure(git_context: true)

      context = :persistent_term.get({AgentWorkshop, :context}, nil)
      assert context =~ "## Git Context"
    end

    test "does not accumulate on repeated calls" do
      Workshop.configure(context: "Base.", git_context: true)
      Workshop.configure(git_context: true)

      context = :persistent_term.get({AgentWorkshop, :context}, nil)

      # Should only have one "## Git Context" block
      parts = String.split(context, "## Git Context")
      assert length(parts) == 2
    end

    test "git_context: false does not inject" do
      Workshop.configure(context: "No git.", git_context: false)

      context = :persistent_term.get({AgentWorkshop, :context}, nil)
      assert context == "No git."
    end
  end

  describe "git_summary/0" do
    test "returns structured map for current repo" do
      {:ok, summary} = Workshop.git_summary()
      assert is_binary(summary.branch)
      assert is_boolean(summary.dirty)
      assert is_list(summary.commits)
    end
  end

  describe "git_diff/0" do
    test "returns diff string" do
      {:ok, diff} = Workshop.git_diff()
      assert is_binary(diff)
    end
  end
end
