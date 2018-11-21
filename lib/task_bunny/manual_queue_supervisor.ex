defmodule TaskBunny.ManualQueues do
  @moduledoc """
  Supervisor to allow for only Specific queues to be started manually.

  This is useful when multiple applications inside of an umbrella application
  use task bunny, you need to launch only the queues specific to a given application

  It supervises Connection and WorkerSupervisor with one_for_all strategy.
  When Connection crashes it restarts all Worker processes through WorkerSupervisor
  so workers can always use a re-established connection.

  You can call this supervisor explicitly like this:
    children = [
      supervisor(TaskBunny.ManualQueues, [[queues: ["myapp.my.queue", "myapp.my.queue_1"]]])
    ]
    Supervisor.start_link(children, [strategy: :one_for_one, name: MyApp.Supervisor])

  Make sure that task_bunny is not a runtime dependency to disable automatic application start. i.e.
    defp deps do
      [
        {:task_bunny, "~> 0.3.2", runtime: false}
      ]
    end
  """
  use Supervisor
  alias TaskBunny.{Connection, Config, Initializer, WorkerSupervisor, PublisherWorker}

  @doc false
  @spec start_link(atom, atom) :: {:ok, pid} | {:error, term}
  def start_link(
        options \\ [],
        name \\ __MODULE__,
        wsv_name \\ WorkerSupervisor,
        ps_name \\ :publisher
      ) do
    Supervisor.start_link(__MODULE__, [wsv_name, ps_name, options], name: name)
  end

  @doc false
  @spec init(list()) ::
          {:ok, {:supervisor.sup_flags(), [Supervisor.Spec.spec()]}}
          | :ignore
  def init([wsv_name, ps_name, options]) do
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

    children = children ++ [supervisor(WorkerSupervisor, [wsv_name, options])]

    supervise(children, strategy: :one_for_all)
  end

  defp publisher_config(name) do
    [
      {:name, {:local, name}},
      {:worker_module, PublisherWorker},
      {:size, Config.publisher_pool_size()},
      {:max_overflow, Config.publisher_max_overflow()}
    ]
  end
end
