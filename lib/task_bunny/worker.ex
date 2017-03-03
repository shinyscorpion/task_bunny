defmodule TaskBunny.Worker do
  @moduledoc """
  A GenServer that listens a queue and consumes messages.
  """

  use GenServer
  require Logger
  alias TaskBunny.{Connection, Consumer, JobRunner, Queue,
                   Publisher, Worker, Message}

  @type t ::%__MODULE__{
    queue: String.t,
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
    queue: nil,
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
  @spec start_link(list) :: GenServer.on_start
  def start_link(config) when is_list(config) do
    %Worker{
      host: config[:host] || :default,
      queue: config[:queue],
      concurrency: config[:concurrency]
    }
    |> start_link()
  end

  @doc """
  Starts a worker given a worker's state
  """
  @spec start_link(t) :: GenServer.on_start
  def start_link(state = %Worker{}) do
    GenServer.start_link(__MODULE__, state, name: pname(state.queue))
  end

  @doc """
  Initialises GenServer. Send a request for RabbitMQ connection
  """
  @spec init(t) :: {:ok, t} | {:stop, :connection_not_ready}
  def init(state = %Worker{}) do
    Logger.info log_msg("initializing", state)

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
    Logger.info log_msg("terminating", state)

    if state.channel do
      AMQP.Channel.close(state.channel)
    end

    :normal
  end

  @doc """
  Stops consuming messages from queue.
  Note this doesn't terminate the process and the jobs currently running will continue so.
  """
  @spec stop_consumer(pid) :: :ok
  def stop_consumer(pid) do
    if Process.alive?(pid), do: send(pid, {:stop_consumer})

    :ok
  end

  @doc """
  Called when connection to RabbitMQ was established.
  Start consumer loop
  """
  @spec handle_info(any, t) ::
    {:noreply, t} |
    {:stop, reason :: term, t}
  def handle_info(message, state)

  def handle_info({:stop_consumer}, state = %Worker{}) do
    if state.channel && state.consumer_tag do
      Logger.info log_msg("stop consuming", state)
      Consumer.cancel(state.channel, state.consumer_tag)
      {:noreply, %{state | consumer_tag: nil}}
    else
      Logger.info log_msg("received :stop_cosumer but already stopped", state)
      {:noreply, state}
    end
  end

  def handle_info({:connected, connection}, state = %Worker{}) do
    # Declares queue
    Queue.declare_with_subqueues(state.host, state.queue)

    # Consumes the queue
    case Consumer.consume(connection, state.queue, state.concurrency) do
      {channel, consumer_tag} ->
        Logger.info log_msg("start comsuming", state)
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
        Logger.debug log_msg("bacic_deliver", state, [body: body])

        JobRunner.invoke(decoded["job"], decoded["payload"], {body, meta})

        {:noreply, %{state | runners: state.runners + 1}}
      error ->
        Logger.error log_msg("bacic_deliver invalid body", state, [body: body, error: error])

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
    Logger.debug log_msg("job_finished", state, [body: body, meta: meta])
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
        _channel -> "#{state.queue} (#{state.consumer_tag})"
      end

    status = %TaskBunny.Status.Worker{
      queue: state.queue,
      runners: state.runners,
      channel: channel,
      stats: state.job_stats,
      consuming: !is_nil(state.consumer_tag)
    }

    {:reply, status, state}
  end

  @spec pname(String.t) :: atom
  defp pname(queue) do
    String.to_atom("TaskBunny.Worker.#{queue}")
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
    {:ok, decoded} = Message.decode(body)
    failed_count = Message.failed_count(decoded)
    job = decoded["job"]
    new_body = Message.add_error_log(body, result)

    case failed_count < job.max_retry() do
      true ->
        Logger.warn log_msg("job failed #{failed_count + 1} times.", state, [body: body, will_be_retried: true])

        retry_message(job, state, new_body, meta)

        {:noreply, update_job_stats(state, :failed)}
      false ->
        # Failed more than X times
        Logger.error log_msg("job failed #{failed_count + 1} times.", state, [body: body, will_be_retried: false])

        reject_message(state, new_body, meta)

        {:noreply, update_job_stats(state, :rejected)}
    end
  end

  @spec retry_message(atom, Worker.t, any, any) :: :ok
  defp retry_message(job, state, body, meta) do
    retry_queue = Queue.retry_queue(state.queue)
    options = [
      expiration: "#{job.retry_interval()}"
    ]
    Publisher.publish(state.host, retry_queue, body, options)

    Consumer.ack(state.channel, meta, true)
    :ok
  end

  @spec reject_message(Worker.t, any, any) :: :ok
  defp reject_message(state, body, meta) do
    rejected_queue = Queue.rejected_queue(state.queue)
    Publisher.publish(state.host, rejected_queue, body)

    Consumer.ack(state.channel, meta, true)
    :ok
  end

  defp log_msg(message, state, additional \\ nil) do
    message = "TaskBunny.Worker: #{message}. Queue: #{state.queue}. Concurrency: #{state.concurrency}. PID: #{inspect self()}."
    if additional do
      "#{message} #{inspect additional}"
    else
      message
    end
  end
end
