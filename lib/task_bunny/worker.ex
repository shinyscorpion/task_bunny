defmodule TaskBunny.Worker do
  @moduledoc """
  A GenServer that listens a queue and consumes messages.
  """

  use GenServer
  require Logger
  alias TaskBunny.{Connection, Consumer, JobRunner, Queue, SyncPublisher, Worker}

  @type t ::%__MODULE__{
    job: atom,
    concurrency: integer,
    channel: AMQP.Channel.t | nil,
    consumer_tag: String.t,
    runners: integer,
    job_stats: %{
      failed: integer,
      succeeded: integer,
      rejected: integer,
    },
  }

  defstruct [
    :job,
    host: :default,
    concurrency: 1,
    channel: nil,
    consumer_tag: nil,
    runners: 0,
    job_stats: %{
      failed: 0,
      succeeded: 0,
      rejected: 0,
    },
  ]

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
        Process.flag(:trap_exit, true)

        {:ok, state}
      _ ->
        {:stop, :connection_not_ready}
    end
  end

  @doc ~S"""
  Closes the AMQP Channel, when the worker exit is captured.
  """
  @spec terminate(any, TaskBunny.Worker.t) :: :normal
  def terminate(_reason, state) do
    if state.channel do
      AMQP.Channel.close(state.channel)
    end

    :normal
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
    case Poison.decode(payload) do
      {:ok, parsed_payload} ->
        Logger.debug "TaskBunny.Worker:(#{state.job}) basic_deliver with #{inspect payload} on #{inspect self()}"
        JobRunner.invoke(state.job, parsed_payload, meta)

        {:noreply, %{state | runners: state.runners + 1}}
      error ->
        Logger.error "TaskBunny.Worker:(#{state.job}) basic_deliver with invalid (#{inspect error}) payload: (#{inspect payload} on #{inspect self()}"

        reject_payload(%{state | runners: state.runners + 1}, payload, meta)
    end
  end

  @doc """
  Called when job was done.
  Acknowledge to RabbitMQ.
  """
  def handle_info({:job_finished, result, payload, meta}, state) do
    Logger.debug "TaskBunny.Worker:(#{state.job}) job_finished with #{inspect payload} on #{inspect self()} with meta #{inspect meta}"
    succeeded = case result do
      :ok -> true
      {:ok, _} -> true
      _ -> false
    end

    failed_count = TaskBunny.Message.failed_count(meta)

    cond do
      succeeded ->
        Consumer.ack(state.channel, meta, true)

        {:noreply, update_job_stats(state, :succeeded)}
      failed_count < state.job.max_retry() ->
        Consumer.ack(state.channel, meta, false)

        {:noreply, update_job_stats(state, :failed)}
      true ->
        # Failed more than X times
        Logger.error "TaskBunny.Worker - job failed #{failed_count + 1} times. TaskBunny stops retrying the job. JOB: #{inspect state.job}. PAYLOAD: #{inspect payload}. ERROR: #{inspect result}"

        # Enqueue failed queue
        reject_payload(state, payload, meta)
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @spec reject_payload(state :: TaskBunny.Worker.t, payload :: any, meta :: any) :: {:noreply, TaskBunny.Worker.t}
  defp reject_payload(state, payload, meta) do
    rejected_queue = Queue.rejected_queue_name(state.job.queue_name())
    SyncPublisher.push(state.host, rejected_queue, payload)

    Consumer.ack(state.channel, meta, true)

    {:noreply, update_job_stats(state, :rejected)}
  end

  @spec pname(job :: atom) :: atom
  defp pname(job) do
    String.to_atom("TaskBunny.Worker.#{job}")
  end

  # Retreive worker status

  def handle_call(:status, _from, state) do
    channel =
      case state.channel do
        nil -> false
        _channel -> "#{state.job.queue_name} (#{state.consumer_tag})"
      end

    status = %TaskBunny.Status.Worker{
      job: state.job,
      runners: state.runners,
      channel: channel,
      stats: state.job_stats,
    }

    {:reply, status, state}
  end

  @spec update_job_stats(state :: TaskBunny.Worker.t, success :: :succeeded | :failed | :rejected) :: TaskBunny.Worker.t
  defp update_job_stats(state, success) do
    stats =
      case success do
        :succeeded -> %{state.job_stats | succeeded: state.job_stats.succeeded + 1}
        :failed -> %{state.job_stats | failed: state.job_stats.failed + 1}
        :rejected -> %{state.job_stats | rejected: state.job_stats.rejected + 1}
      end

    %{state | runners: state.runners - 1, job_stats: stats}
  end
end
