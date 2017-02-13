defmodule TaskBunny do
  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias TaskBunny.Status

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    register_metrics()

    # Define workers and child supervisors to be supervised
    children = [
      supervisor(TaskBunny.Supervisor, [])
    ]

    opts = [strategy: :one_for_one, name: TaskBunny]
    Supervisor.start_link(children, opts)
  end

  defp register_metrics do
    if Code.ensure_loaded(Wobserver) == {:module, Wobserver} do
      Wobserver.register :page, {"Task Bunny", :taskbunny, &Status.page/0}
      Wobserver.register :metric, [&Status.metrics/0]
    end
  end
end
