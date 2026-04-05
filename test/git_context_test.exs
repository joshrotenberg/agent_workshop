defmodule AgentWorkshop.GitContextTest do
  use ExUnit.Case, async: true

  alias AgentWorkshop.GitContext

  @moduletag :git_context

  setup do
    dir = Path.join(System.tmp_dir!(), "workshop_git_test_#{:rand.uniform(100_000)}")
    File.mkdir_p!(dir)

    # Init a real git repo
    System.cmd("git", ["init", "--initial-branch=main", dir])
    System.cmd("git", ["config", "user.name", "Test"], cd: dir)
    System.cmd("git", ["config", "user.email", "test@test.com"], cd: dir)

    # Create initial commit
    File.write!(Path.join(dir, "README.md"), "# Test\n")
    System.cmd("git", ["add", "."], cd: dir)
    System.cmd("git", ["commit", "-m", "initial commit"], cd: dir)

    on_exit(fn -> File.rm_rf!(dir) end)

    {:ok, dir: dir}
  end

  describe "build/1" do
    test "returns context string for a git repo", %{dir: dir} do
      ctx = GitContext.build(working_dir: dir)
      assert is_binary(ctx)
      assert ctx =~ "## Git Context"
      assert ctx =~ "Branch: main"
      assert ctx =~ "(clean)"
      assert ctx =~ "initial commit"
    end

    test "includes dirty status when files are modified", %{dir: dir} do
      File.write!(Path.join(dir, "new.txt"), "hello")
      ctx = GitContext.build(working_dir: dir)
      assert ctx =~ "(dirty)"
      assert ctx =~ "1 untracked"
      assert ctx =~ "new.txt"
    end

    test "includes staged files", %{dir: dir} do
      File.write!(Path.join(dir, "staged.txt"), "staged")
      System.cmd("git", ["add", "staged.txt"], cd: dir)
      ctx = GitContext.build(working_dir: dir)
      assert ctx =~ "1 staged"
    end

    test "returns nil for non-git directory" do
      dir = Path.join(System.tmp_dir!(), "not_a_repo_#{:rand.uniform(100_000)}")
      File.mkdir_p!(dir)
      result = GitContext.build(working_dir: dir)
      assert result == nil
      File.rm_rf!(dir)
    end

    test "shows recent commits", %{dir: dir} do
      File.write!(Path.join(dir, "a.txt"), "a")
      System.cmd("git", ["add", "."], cd: dir)
      System.cmd("git", ["commit", "-m", "second commit"], cd: dir)

      ctx = GitContext.build(working_dir: dir)
      assert ctx =~ "Recent commits:"
      assert ctx =~ "second commit"
      assert ctx =~ "initial commit"
    end
  end

  describe "summary/1" do
    test "returns structured map", %{dir: dir} do
      {:ok, summary} = GitContext.summary(working_dir: dir)
      assert summary.branch == "main"
      assert summary.dirty == false
      assert summary.staged == 0
      assert summary.unstaged == 0
      assert summary.untracked == 0
      assert is_list(summary.commits)
      assert is_binary(summary.sha)
    end

    test "reflects dirty state", %{dir: dir} do
      File.write!(Path.join(dir, "dirty.txt"), "dirty")
      {:ok, summary} = GitContext.summary(working_dir: dir)
      assert summary.dirty == true
      assert summary.untracked == 1
    end

    test "returns error for non-git directory" do
      dir = Path.join(System.tmp_dir!(), "not_a_repo_#{:rand.uniform(100_000)}")
      File.mkdir_p!(dir)
      result = GitContext.summary(working_dir: dir)
      assert {:error, _} = result
      File.rm_rf!(dir)
    end
  end

  describe "changes/1" do
    test "returns empty diff for clean repo", %{dir: dir} do
      {:ok, diff} = GitContext.changes(working_dir: dir)
      assert diff == ""
    end

    test "returns diff for modified files", %{dir: dir} do
      File.write!(Path.join(dir, "README.md"), "# Test\nModified\n")
      {:ok, diff} = GitContext.changes(working_dir: dir)
      assert diff =~ "Modified"
    end
  end
end
