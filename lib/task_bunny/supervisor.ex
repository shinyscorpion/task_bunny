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

  @spec start_link(atom) :: {:ok, pid} | {:error, term}
  def start_link(name \\ __MODULE__, wsv_name \\ WorkerSupervisor) do
    Supervisor.start_link(__MODULE__, [wsv_name], name: name)
  end

  @spec init(list()) ::
    {:ok, {:supervisor.sup_flags, [Supervisor.Spec.spec]}} |
    :ignore
  def init([wsv_name]) do
    # Add Connection severs for each hosts
    connections = Enum.map Config.hosts(), fn (host) ->
      worker(Connection, [host])
    end

    # Define workers and child supervisors to be supervised
    children =
      case Config.auto_start?() do
        true ->
          connections ++ [supervisor(WorkerSupervisor, [wsv_name])]
        false ->
          []
      end

    supervise(children, strategy: :one_for_all)
  end
end
