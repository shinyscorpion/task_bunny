defmodule TaskBunny.Supervisor do
  @moduledoc """
  Main supervisor for TaskBunny.

  It supervises Connection and WorkerSupervisor with one_for_all strategy.
  When Connection crashes it restarts all Worker processes through WorkerSupervisor
  so workers can always use a re-established connection.

  You don't have to call or start the Supervisor explicity.
  It will be automatically started by application and
  configure child processes based on configuration file.
  """
  use Supervisor
  alias TaskBunny.{Connection, Config, Initializer, WorkerSupervisor}

  @doc false
  @spec start_link(atom, atom) :: {:ok, pid} | {:error, term}
  def start_link(name \\ __MODULE__, wsv_name \\ WorkerSupervisor) do
    Supervisor.start_link(__MODULE__, [wsv_name], name: name)
  end

  @doc false
  @spec init(list()) ::
          {:ok, {:supervisor.sup_flags(), [Supervisor.Spec.spec()]}}
          | :ignore
  def init([wsv_name]) do
    # Add Connection severs for each hosts
    connections =
      Enum.map(Config.hosts(), fn host ->
        worker(Connection, [host], id: make_ref())
      end)

    children =
      case Initializer.alive?() do
        true -> connections
        false -> connections ++ [worker(Initializer, [false])]
      end

    # Define workers and child supervisors to be supervised
    children =
      case {Config.auto_start?(), Config.disable_worker?()} do
        {true, false} ->
          children ++ [supervisor(WorkerSupervisor, [wsv_name])]

        {true, true} ->
          # Only connections
          children

        _ ->
          []
      end

    supervise(children, strategy: :one_for_all)
  end
end
