defmodule TaskBunny.Worker do
  @moduledoc """
  A GenServer that listens a queue and consumes messages.
  """

  use GenServer
  require Logger
  alias TaskBunny.{Connection, Consumer, JobRunner, Queue,
                   Publisher, Worker, Message}

  @type t ::%__MODULE__{
    job: atom,
    host: atom,
    concurrency: integer,
    channel: AMQP.Channel.t | nil,
    consumer_tag: String.t | nil,
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
  @spec start_link({atom, integer}) :: GenServer.on_start
  def start_link({job, concurrency}) do
    start_link(%Worker{job: job, concurrency: concurrency})
  end

  @doc """
  Starts a worker for a job with concurrency on the host
  """
  @spec start_link({atom, atom, integer}) :: GenServer.on_start
  def start_link({host, job, concurrency}) do
    start_link(%Worker{host: host, job: job, concurrency: concurrency})
  end

  @doc """
  Starts a worker given a worker's state
  """
  @spec start_link(t) :: GenServer.on_start
  def start_link(state = %Worker{}) do
    GenServer.start_link(__MODULE__, state, name: pname(state.job))
  end

  @doc """
  Initialises GenServer. Send a request for RabbitMQ connection
  """
  @spec init(t) :: {:ok, t} | {:stop, :connection_not_ready}
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
    Logger.info "TaskBunny.Worker termintating: PID: #{inspect self()}"

    if state.channel do
      AMQP.Channel.close(state.channel)
    end

    :normal
  end

  @doc """
  Called when connection to RabbitMQ was established.
  Start consumer loop
  """
  @spec handle_info(any, t) ::
    {:noreply, t} |
    {:stop, reason :: term, t}
  def handle_info(message, state)

  def handle_info({:connected, connection}, state = %Worker{}) do
    # Declares queue
    state.job.declare_queue(state.host)

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
  def handle_info({:basic_deliver, body, meta}, state) do
    case Message.decode(body) do
      {:ok, decoded} ->
        Logger.debug "TaskBunny.Worker:(#{state.job}) basic_deliver with #{inspect body} on #{inspect self()}"
        JobRunner.invoke(state.job, decoded["payload"], {body, meta})

        {:noreply, %{state | runners: state.runners + 1}}
      error ->
        Logger.error "TaskBunny.Worker:(#{state.job}) basic_deliver with invalid (#{inspect error}) payload: (#{inspect body} on #{inspect self()}"

        reject_message(state, body, meta)

        # Needs state.runners + 1, because reject_payload does state.runners - 1
        state = %{state | runners: state.runners + 1}
        {:noreply, update_job_stats(state, :rejected)}
    end
  end

  @doc """
  Called when job was done.
  Acknowledge to RabbitMQ.
  """
  def handle_info({:job_finished, result, {body, meta}}, state) do
    Logger.debug "TaskBunny.Worker:(#{state.job}) job_finished with #{inspect body} on #{inspect self()} with meta #{inspect meta}"
    case succeeded?(result) do
      true ->
        Consumer.ack(state.channel, meta, true)

        {:noreply, update_job_stats(state, :succeeded)}
      false ->
        handle_failed_job(state, body, meta, result)
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # Retreive worker status
  @spec handle_call(atom, {pid, any}, any) :: {:reply, map, t}
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

  @spec pname(job :: atom) :: atom
  defp pname(job) do
    String.to_atom("TaskBunny.Worker.#{job}")
  end

  @spec update_job_stats(Worker.t, :succeeded | :failed | :rejected) :: Worker.t
  defp update_job_stats(state, success) do
    stats =
      case success do
        :succeeded -> %{state.job_stats | succeeded: state.job_stats.succeeded + 1}
        :failed -> %{state.job_stats | failed: state.job_stats.failed + 1}
        :rejected -> %{state.job_stats | rejected: state.job_stats.rejected + 1}
      end

    %{state | runners: state.runners - 1, job_stats: stats}
  end

  defp succeeded?(:ok), do: true
  defp succeeded?({:ok, _}), do: true
  defp succeeded?(_), do: false

  defp handle_failed_job(state, body, meta, result) do
    failed_count = Message.failed_count(meta)

    case failed_count < state.job.max_retry() do
      true ->
        Logger.warn "TaskBunny.Worker - job failed #{failed_count + 1} times. TaskBunny will retry the job. JOB: #{inspect state.job}. MESSAGE: #{inspect body}. ERROR: #{inspect result}"

        Consumer.ack(state.channel, meta, false)

        {:noreply, update_job_stats(state, :failed)}
      false ->
        # Failed more than X times
        Logger.error "TaskBunny.Worker - job failed #{failed_count + 1} times. TaskBunny stops retrying the job. JOB: #{inspect state.job}. PAYLOAD: #{inspect body}. ERROR: #{inspect result}"

        reject_message(state, body, meta)

        {:noreply, update_job_stats(state, :rejected)}
    end
  end

  @spec retry_message(Worker.t, any, any) :: :ok
  defp retry_message(state, body, meta) do
    retry_queue = Queue.retry_queue_name(state.job.queue_name())
    # TODO: set TTL
    SyncPublisher.push(state.host, retry_queue, body)

    Consumer.ack(state.channel, meta, true)
    :ok
  end

  @spec reject_message(Worker.t, any, any) :: :ok
  defp reject_message(state, body, meta) do
    rejected_queue = Queue.rejected_queue_name(state.job.queue_name())
    Publisher.publish(state.host, rejected_queue, body)

    Consumer.ack(state.channel, meta, true)
    :ok
  end
end
