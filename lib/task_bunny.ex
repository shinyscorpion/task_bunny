defmodule TaskBunny do
  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  alias TaskBunny.Experimental.{Config, Connection}

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    # Define workers and child supervisors to be supervised
    children = [
    ]

    # Add Connection severs for each hosts
    children = children ++ Enum.map(Config.hosts(), fn (host) ->
      worker(Connection, [{host}])
    end)

    # TODO:
    # We might want to supervise workers here too.
    # Each workers should belong to one host and stay under the same supervisor
    # so that supervisor can restart worker when connection process was died.
    opts = [strategy: :one_for_one, name: TaskBunny.MainSupervisor]
    Supervisor.start_link(children, opts)
  end
end
