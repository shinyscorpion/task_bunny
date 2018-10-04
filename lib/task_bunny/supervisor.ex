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
  alias TaskBunny.{Connection, Config, Initializer, WorkerSupervisor, PublisherWorker}

  @doc false
  @spec start_link(atom, atom) :: {:ok, pid} | {:error, term}
  def start_link(name \\ __MODULE__, wsv_name \\ WorkerSupervisor, ps_name \\ :publisher) do
    Supervisor.start_link(__MODULE__, [wsv_name, ps_name], name: name)
  end

  @doc false
  @spec init(list()) ::
          {:ok, {:supervisor.sup_flags(), [Supervisor.Spec.spec()]}}
          | :ignore
  def init([wsv_name, ps_name]) do
    # Add Connection severs for each hosts
    connections =
      Enum.map(
        Config.hosts(),
        fn host ->
          worker(Connection, [host], id: make_ref())
        end
      )

    publisher = [:poolboy.child_spec(:publisher, publisher_config(ps_name))]

    children =
      case Initializer.alive?() do
        true -> connections ++ publisher
        false -> connections ++ publisher ++ [worker(Initializer, [false])]
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

  defp publisher_config(name) do
    [
      {:name, {:local, name}},
      {:worker_module, PublisherWorker},
      {:size, 15},
      {:max_overflow, 0}
    ]
  end
end
