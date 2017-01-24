defmodule TaskBunny.Experimental.Worker do
  @moduledoc """
  A GenServer that listens a queue and consumes messages.
  """

  use GenServer
  require Logger
  alias TaskBunny.JobRunner
  alias TaskBunny.Experimental.{Connection,Consumer,Worker}

  defstruct [:job, host: :default, concurrency: 1, channel: nil, consumer_tag: nil]

  @doc """
  Starts a worker for a job with concurrency
  """
  @spec start_link({job :: atom, concurrency :: integer}) :: GenServer.on_start
  def start_link({job, concurrency}) do
    start_link(%Worker{job: job, concurrency: concurrency})
  end

  @doc """
  Starts a worker for a job with concurrency on the host
  """
  @spec start_link({host :: atom, job :: atom, concurrency :: integer}) :: GenServer.on_start
  def start_link({host, job, concurrency}) do
    start_link(%Worker{host: host, job: job, concurrency: concurrency})
  end

  @nodoc
  def start_link(state = %Worker{}) do
    GenServer.start_link(__MODULE__, state, name: pname(state.job))
  end

  @doc """
  Initialises GenServer. Send a request for RabbitMQ connection
  """
  def init(state = %Worker{}) do
    Logger.info "TaskBunny.Worker initializing with #{inspect state.job} and maximum #{inspect state.concurrency} concurrent jobs: PID: #{inspect self()}"

    case Connection.monitor_connection(state.host, self()) do
      :ok ->
        {:ok, state}
      _ ->
        {:stop, :connection_not_ready}
    end
  end

  @doc """
  Called when connection to RabbitMQ was established.
  Start consumer loop
  """
  def handle_info({:connected, connection}, state = %Worker{}) do
    case Consumer.consume(connection, state.job.queue_name, state.concurrency) do
      {channel, consumer_tag} ->
        Logger.info "TaskBunny.Worker: start consuming #{inspect state.job}. PID: #{inspect self()}"
        {:noreply, %{state | channel: channel, consumer_tag: consumer_tag}}
      error ->
        {:stop, {:failed_to_consume, error}, state}
    end
  end

  @doc """
  Called when message was delivered from RabbitMQ.
  Invokes a job here.
  """
  def handle_info({:basic_deliver, payload, meta}, state) do
    JobRunner.invoke(state.job, Poison.decode!(payload), meta)

    {:noreply, state}
  end

  @doc """
  Called when job was done.
  Acknowledge to RabbitMQ.
  """
  def handle_info({:job_finished, result, meta}, state) do
    succeeded = case result do
      :ok -> true
      {:ok, _} -> true
      _ -> false
    end

    Consumer.ack(state.channel, meta, succeeded)

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @spec pname(job :: atom) :: atom
  defp pname(job) do
    String.to_atom("TaskBunny.Worker.#{job}")
  end
end
