defmodule TaskBunny do
  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  alias TaskBunny.Experimental.{Config, Connection}

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    jobs = [
      {TaskBunny.Experimental.SampleJobs.HelloJob, 5}
    ]

    # Define workers and child supervisors to be supervised
    children = [
      supervisor(TaskBunny.WorkerSupervisor, [jobs])
    ]

    # Add Connection severs for each hosts
    children = children ++ Enum.map(Config.hosts(), fn (host) ->
      worker(Connection, [{host, nil}])
    end)

    # TODO:
    # We might want to supervise workers here too.
    # Each workers should belong to one host and stay under the same supervisor
    # so that supervisor can restart worker when connection process was died.
    opts = [strategy: :one_for_all, name: TaskBunny.MainSupervisor]
    Supervisor.start_link(children, opts)
  end
end
