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
    children = Enum.map(Config.hosts(), fn (host) ->
      worker(Connection, [host])
    end) ++ children

    opts = [strategy: :one_for_all, name: TaskBunny.MainSupervisor]
    Supervisor.start_link(children, opts)
  end
end
