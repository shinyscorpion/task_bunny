defmodule TaskBunny.Supervisor do
  @moduledoc """
  Main supervisor for TaskBunny.

  It supervises Connection and WorkerSupervisor with one_for_all strategy.
  When Connection crashes, it will restart all Worker through WorkerSupervisor
  so workers can always use re-established connection.

  It loads RabbitMQ hosts and workers from config.
  """

  use Supervisor
  alias TaskBunny.{Connection, Config, WorkerSupervisor}

  def start_link() do
    Supervisor.start_link(__MODULE__, [])
  end

  def init([]) do
    # Define workers and child supervisors to be supervised
    children = [
      supervisor(WorkerSupervisor, [get_jobs()])
    ]

    # Add Connection severs for each hosts
    connections = Enum.map Config.hosts(), fn (host) ->
      worker(Connection, [host])
    end

    children = if Config.auto_start?() do
        connections ++ children
      else
        []
      end

    supervise(children, strategy: :one_for_all)
  end

  defp get_jobs do
    Config.jobs()
    |> Enum.map(fn (job) ->
      {job[:host] || :default, job[:job], job[:concurrency]}
    end)
  end
end
