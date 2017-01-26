defmodule TaskBunny.Worker do
  @moduledoc """
  A GenServer that listens a queue and consumes messages.
  """

  use GenServer
  require Logger
  alias TaskBunny.{Connection, Consumer, JobRunner, Queue, SyncPublisher, Worker}

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

  @doc false
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
    # Declares queue
    state.job.declare_queue(connection)

    # Consumes the queue
    case Consumer.consume(connection, state.job.queue_name(), state.concurrency) do
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
    Logger.debug "TaskBunny.Worker: basic_deliver with #{inspect payload} on #{inspect self()}"
    JobRunner.invoke(state.job, Poison.decode!(payload), meta)

    {:noreply, state}
  end

  @doc """
  Called when job was done.
  Acknowledge to RabbitMQ.
  """
  def handle_info({:job_finished, result, payload, meta}, state) do
    succeeded = case result do
      :ok -> true
      {:ok, _} -> true
      _ -> false
    end

    failed_count = TaskBunny.Message.failed_count(meta)

    cond do
      succeeded ->
        Consumer.ack(state.channel, meta, true)
      failed_count < state.job.max_retry() ->
        Consumer.ack(state.channel, meta, false)
      true ->
        # Failed more than X times
        Logger.error "TaskBunny.Worker - job failed #{failed_count + 1} times. TaskBunny stops retrying the job. JOB: #{inspect state.job}. PAYLOAD: #{inspect payload}. ERROR: #{inspect result}"

        # Enqueue failed queue
        failed_queue = Queue.failed_queue_name(state.job.queue_name())
        SyncPublisher.push(state.host, failed_queue, payload)

        Consumer.ack(state.channel, meta, true)
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @spec pname(job :: atom) :: atom
  defp pname(job) do
    String.to_atom("TaskBunny.Worker.#{job}")
  end
end
