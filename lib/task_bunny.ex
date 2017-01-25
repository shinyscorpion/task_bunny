defmodule TaskBunny do
  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    # Define workers and child supervisors to be supervised
    children = [
      supervisor(TaskBunny.Supervisor, [])
    ]

    opts = [strategy: :one_for_one, name: TaskBunny]
    Supervisor.start_link(children, opts)
  end
end
