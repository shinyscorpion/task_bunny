defmodule TaskBunny.Worker do
  @moduledoc """
  Todo: Add documentation.
  """

  use GenServer

  require Logger

  alias TaskBunny.{
    Connection,
    JobRunner,
    Worker,
  }

  @typedoc ~S"""
  The state of the Worker.

  Contains:
    - `job`, the job for the worker.
    - `concurrency`, the amount of concurrent job runners for the worker.
    - `channel`, the AMQP channel used by the worker.
    - `connection`, the AMQP connection used by the worker.
  """
  @type t ::%__MODULE__{job: atom, concurrency: integer, channel: AMQP.Channel.t | nil, connection: AMQP.Connection.t | nil, consumer_tag: String.t}

  @doc ~S"""
  The state of the Worker.

  Contains:
    - `job`, the job for the worker.
    - `concurrency`, the amount of concurrent job runners for the worker.
    - `channel`, the AMQP channel used by the worker.
    - `connection`, the AMQP connection used by the worker.
  """
  @enforce_keys [:job]
  defstruct [:job, concurrency: 1, channel: nil, connection: nil, consumer_tag: nil]

  def start_link({job, concurrency}) do
    GenServer.start_link(__MODULE__, {job, concurrency}, name: job)
  end

  def init({job, concurrency}) do
    Logger.info "TaskBunny.Worker initializing with #{inspect job} and maximum #{inspect concurrency} concurrent jobs: PID: #{inspect self()}"
    result = Connection.subscribe()

    if result != :ok, do: raise "Can not subscribe to the connection."

    {:ok, %Worker{job: job, concurrency: concurrency}}
  end

  def handle_info({:basic_deliver, payload, meta}, state) do
    JobRunner.invoke(state.job, Poison.decode!(payload), meta)

    {:noreply, state}
  end

  def handle_info({:job_finished, result, meta}, state) do
    succeeded = case result do
      :ok -> true
      {:ok, _} -> true
      _ -> false
    end

    TaskBunny.WorkerChannel.ack(state.channel, meta, succeeded)

    {:noreply, state}
  end

  # Seperate this in different module for use?

  def handle_info(:no_connection, state) do
    Logger.info "TaskBunny.Worker.#{state.job}: Lost Connection"

    {:noreply, %{state| connection: nil, channel: nil, consumer_tag: nil}}
  end

  def handle_info({:connection, connection}, state) do
    Logger.info "TaskBunny.Worker.#{state.job}: New connection #{inspect(connection)}"

    state = %{state | connection: connection}

    {:noreply, TaskBunny.WorkerChannel.connect(state)}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end