defmodule AgentWorkshop.BoardWorker do
  @moduledoc """
  A board-aware agent that polls for work, claims it, executes, and reports.

  Combines an agent (from a profile), a scheduler, and the work board
  into a single first-class concept. The worker:

  1. Polls the board for `:ready` items matching its work type
  2. Claims the highest priority item
  3. Sends the item's title + spec as a prompt to its agent
  4. Marks the item complete (or failed) based on the result
  5. Repeats

  ## Usage

      board_worker(:coder_1, :code, profile: :coder, interval: :timer.minutes(1))
      board_worker(:reviewer_1, :review, profile: :reviewer, interval: :timer.minutes(2))

      # Post work — workers pick it up automatically
      work(:checkout, "Implement git checkout", type: :code, spec: "...")
      work(:checkout_review, "Review checkout", type: :review, depends_on: [:checkout])
  """

  use GenServer

  alias AgentWorkshop.{PubSub, Telemetry, Work, Workshop}

  @registry AgentWorkshop.BoardWorker.Registry

  defstruct [
    :agent_name,
    :work_type,
    :interval,
    :timer_ref,
    worktree: false,
    claims_completed: 0,
    current_item: nil
  ]

  # ── Client API ──────────────────────────────────────────────

  @doc false
  def start_link(opts) do
    agent_name = Keyword.fetch!(opts, :agent_name)
    GenServer.start_link(__MODULE__, opts, name: via(agent_name))
  end

  @doc false
  def stop(agent_name) do
    case Registry.lookup(@registry, agent_name) do
      [{pid, _}] ->
        try do
          GenServer.stop(pid, :normal, 3_000)
        catch
          :exit, _ ->
            if Process.alive?(pid), do: Process.exit(pid, :kill)
        end

      [] ->
        :ok
    end
  end

  @doc false
  def get_info(agent_name) do
    case Registry.lookup(@registry, agent_name) do
      [{pid, _}] -> GenServer.call(pid, :info)
      [] -> nil
    end
  catch
    :exit, _ -> nil
  end

  @doc false
  def list_all do
    @registry
    |> Registry.select([{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.filter(fn {_name, pid} -> Process.alive?(pid) end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.sort()
  end

  @doc false
  def start_registry do
    case Registry.start_link(keys: :unique, name: @registry) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end

  # ── GenServer callbacks ─────────────────────────────────────

  @impl true
  def init(opts) do
    agent_name = Keyword.fetch!(opts, :agent_name)
    work_type = Keyword.fetch!(opts, :work_type)
    interval = Keyword.fetch!(opts, :interval)
    worktree = Keyword.get(opts, :worktree, false)

    state = %__MODULE__{
      agent_name: agent_name,
      work_type: work_type,
      interval: interval,
      worktree: worktree
    }

    timer_ref = Process.send_after(self(), :poll, interval)
    {:ok, %{state | timer_ref: timer_ref}}
  end

  @impl true
  def handle_info(:poll, state) do
    state = try_claim_and_execute(state)
    timer_ref = Process.send_after(self(), :poll, state.interval)
    {:noreply, %{state | timer_ref: timer_ref}}
  end

  def handle_info({:work_done, _item_id}, state) do
    {:noreply, %{state | claims_completed: state.claims_completed + 1, current_item: nil}}
  end

  def handle_info({:work_failed, _item_id}, state) do
    {:noreply, %{state | claims_completed: state.claims_completed + 1, current_item: nil}}
  end

  # Task result messages from cast — ignore (watcher handles completion)
  def handle_info({ref, _result}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, state}
  end

  # Task DOWN messages
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_call(:info, _from, state) do
    info = %{
      agent_name: state.agent_name,
      work_type: state.work_type,
      interval: state.interval,
      worktree: state.worktree,
      claims_completed: state.claims_completed,
      current_item: state.current_item
    }

    {:reply, info, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)
    :ok
  end

  # ── Internal ────────────────────────────────────────────────
  #
  # Poll/claim/execute/complete cycle:
  #
  #   1. POLL  -- on each :poll timer tick, check the work board for :ready
  #              items matching this worker's work_type.
  #   2. CLAIM -- atomically claim the highest-priority item so no other
  #              worker picks it up (Work.claim/2 fails if already claimed).
  #   3. EXECUTE -- mark the item :in_progress and send its title+spec as a
  #              prompt via Workshop.cast/2 (non-blocking).
  #   4. COMPLETE -- a spawned watcher polls the agent's status; when the
  #              agent becomes :idle, it reads the result and calls
  #              Work.complete/2 or Work.fail/2. The agent is then reset
  #              so it starts fresh for the next item.

  defp try_claim_and_execute(state) do
    # Check if agent is busy
    case Workshop.info(state.agent_name) do
      %{status: :working} ->
        state

      _ ->
        claim_next(state)
    end
  rescue
    _ -> state
  end

  defp claim_next(state) do
    ready_items = Work.list(status: :ready, type: state.work_type)

    case ready_items do
      [] ->
        state

      [item | _] ->
        case Work.claim(item.id, state.agent_name) do
          :ok ->
            execute_item(item, state)

          {:error, _} ->
            state
        end
    end
  end

  defp execute_item(item, state) do
    Work.start_work(item.id)
    Telemetry.event(:board_worker_started, %{}, %{agent: state.agent_name, item: item.id})
    PubSub.broadcast({:board_worker, :started, state.agent_name, item.id})

    prompt = build_prompt(item)

    # Use cast so we don't block the poll loop
    Workshop.cast(state.agent_name, prompt)

    # Start a supervised watcher that polls the agent until it finishes,
    # then marks the work item complete or failed.
    worker_pid = self()
    tasks_sup = AgentWorkshop.Workshop.TasksSupervisor

    Task.Supervisor.start_child(tasks_sup, fn ->
      watch_completion(state.agent_name, item.id, worker_pid)
    end)

    %{state | current_item: item.id}
  end

  defp watch_completion(agent_name, item_id, worker_pid) do
    Process.sleep(2_000)

    case Workshop.info(agent_name) do
      %{status: :idle} ->
        result_text = Workshop.result(agent_name)
        Work.complete(item_id, result_text)
        Telemetry.event(:board_worker_completed, %{}, %{agent: agent_name, item: item_id})
        PubSub.broadcast({:board_worker, :completed, agent_name, item_id})
        # Reset agent session so it starts fresh for the next work item
        Workshop.reset(agent_name)
        send(worker_pid, {:work_done, item_id})

      %{status: :working} ->
        watch_completion(agent_name, item_id, worker_pid)

      _ ->
        Work.fail(item_id, "agent unavailable")
        send(worker_pid, {:work_failed, item_id})
    end
  rescue
    _ ->
      Work.fail(item_id, "watcher crashed")
      send(worker_pid, {:work_failed, item_id})
  end

  defp build_prompt(item) do
    if item.spec do
      "#{item.title}\n\nSpec:\n#{item.spec}"
    else
      item.title
    end
  end

  defp via(agent_name) do
    {:via, Registry, {@registry, agent_name}}
  end
end
