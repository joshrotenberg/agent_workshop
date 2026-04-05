defmodule AgentWorkshop.Application do
  @moduledoc false
  use Application

  # Supervision tree start order matters:
  #
  #   1. TableManager   -- must be first; creates and owns all ETS tables so
  #                        that every downstream process can read/write on init.
  #   2. Global config  -- :persistent_term defaults (backend, query_opts, context).
  #                        No process needed; reads are free.
  #   3. Registries     -- PubSub (duplicate keys for fan-out), Scheduler and
  #                        BoardWorker (unique keys for named lookup).
  #   4. EventLog       -- subscribes to the PubSub registry on init, so the
  #                        registry must already be running.
  #   5. Persistence    -- subscribes to PubSub; writes state to disk on change.
  #                        Idle until enabled via configure(persistence: ...).
  #   6. DynamicSupervisor / TaskSupervisor -- started last because nothing
  #                        depends on them at boot; agents are added later via
  #                        Workshop.agent/2.

  def start(_type, _args) do
    AgentWorkshop.Workshop.init_global_state()

    children = [
      AgentWorkshop.TableManager,
      {Registry, keys: :duplicate, name: AgentWorkshop.PubSub.Registry},
      {Registry, keys: :unique, name: AgentWorkshop.Scheduler.Registry},
      {Registry, keys: :unique, name: AgentWorkshop.BoardWorker.Registry},
      AgentWorkshop.EventLog,
      AgentWorkshop.Persistence,
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
