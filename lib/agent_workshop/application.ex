defmodule AgentWorkshop.Application do
  @moduledoc false
  use Application

  # Supervision tree start order matters:
  #
  #   1. TableManager   -- must be first; creates and owns all ETS tables so
  #                        that every downstream process can read/write on init.
  #   2. Agent (state)  -- global config map (backend, query_opts, context).
  #   3. Registries     -- PubSub (duplicate keys for fan-out), Scheduler and
  #                        BoardWorker (unique keys for named lookup).
  #   4. EventLog       -- subscribes to the PubSub registry on init, so the
  #                        registry must already be running.
  #   5. DynamicSupervisor / TaskSupervisor -- started last because nothing
  #                        depends on them at boot; agents are added later via
  #                        Workshop.agent/2.

  def start(_type, _args) do
    children = [
      AgentWorkshop.TableManager,
      %{
        id: :agent_workshop_state,
        start:
          {Agent, :start_link,
           [fn -> AgentWorkshop.Workshop.default_state() end, [name: :agent_workshop_state]]}
      },
      {Registry, keys: :duplicate, name: AgentWorkshop.PubSub.Registry},
      {Registry, keys: :unique, name: AgentWorkshop.Scheduler.Registry},
      {Registry, keys: :unique, name: AgentWorkshop.BoardWorker.Registry},
      AgentWorkshop.EventLog,
      {DynamicSupervisor,
       name: AgentWorkshop.Workshop.SessionsSupervisor, strategy: :one_for_one},
      {Task.Supervisor, name: AgentWorkshop.Workshop.TasksSupervisor}
    ]

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: AgentWorkshop.Supervisor
    )
  end
end
