defmodule TaskBunny.Queue do
  @moduledoc """
  Convenience functions for accessing TaskBunny queues.

  It's a semi private module normally wrapped by other modules.

  ## Sub Queues

  When TaskBunny creates(declares) a queue on RabbitMQ, it also creates the following sub queues.

  - [queue-name].scheduled: holds jobs to be executed in the future
  - [queue-name].retry: holds jobs to be retried
  - [queue-name].rejected: holds jobs that were rejected (failed more than max retry times or wrong message format)
  """

  @doc """
  Declares a queue with sub queues.

      Queue.declare_with_subqueues(:default, "normal_jobs")

  For this call, the function creates(declares) three queues:

  - normal_jobs: a queue that holds jobs to process
  - normal_jobs.scheduled: a queue that holds jobs to process in the future
  - normal_jobs.retry: a queue that holds jobs failed and waiting to retry
  - normal_jobs.rejected: a queue that holds jobs failed and won't be retried

  """
  @spec declare_with_subqueues(%AMQP.Connection{} | atom, String.t) :: {map, map, map, map}
  def declare_with_subqueues(host, work_queue) when is_atom(host) do
    conn = TaskBunny.Connection.get_connection!(host)
    declare_with_subqueues(conn, work_queue)
  end

  def declare_with_subqueues(connection, work_queue) do
    {:ok, channel} = AMQP.Channel.open(connection)

    scheduled_queue = scheduled_queue(work_queue)
    retry_queue = retry_queue(work_queue)
    rejected_queue = rejected_queue(work_queue)

    work = declare(channel, work_queue, [durable: true])
    rejected = declare(channel, rejected_queue, [durable: true])

    # Set main queue as dead letter exchange of retry queue.
    # It will requeue the message once message TTL is over.
    retry_options = [
      arguments: [
        {"x-dead-letter-exchange", :longstr, ""},
        {"x-dead-letter-routing-key", :longstr, work_queue}
      ],
      durable: true
    ]
    retry = declare(channel, retry_queue, retry_options)

    scheduled_options = [
      arguments: [
        {"x-dead-letter-exchange", :longstr, ""},
        {"x-dead-letter-routing-key", :longstr, work_queue}
      ],
      durable: true
    ]
    scheduled = declare(channel, scheduled_queue, scheduled_options)

    AMQP.Channel.close(channel)

    {work, retry, rejected, scheduled}
  end

  @doc """
  Deletes the queue and its subqueues.
  """
  @spec delete_with_subqueues(%AMQP.Connection{} | atom, String.t) :: :ok
  def delete_with_subqueues(host, work_queue) when is_atom(host) do
    conn = TaskBunny.Connection.get_connection!(host)
    delete_with_subqueues(conn, work_queue)
  end

  def delete_with_subqueues(connection, work_queue) do
    {:ok, channel} = AMQP.Channel.open(connection)

    work_queue
    |> queue_with_subqueues()
    |> Enum.each(fn (queue) ->
      AMQP.Queue.delete(channel, queue)
    end)

    AMQP.Channel.close(channel)
    :ok
  end

  @doc false
  # Declares a single queue with the options
  @spec declare(%AMQP.Channel{}, String.t, keyword) :: map
  def declare(channel, queue, options \\ []) do
    options = options ++ [durable: true]
    {:ok, state} = AMQP.Queue.declare(channel, queue, options)

    state
  end

  @doc """
  Returns the message count and consumer count for the given queue.
  """
  @spec state(%AMQP.Connection{} | atom, String.t) :: map
  def state(host_or_conn \\ :default, queue)

  def state(host, queue) when is_atom(host) do
    conn = TaskBunny.Connection.get_connection!(host)
    state(conn, queue)
  end

  def state(connection, queue) do
    {:ok, channel} = AMQP.Channel.open(connection)
    {:ok, state} = AMQP.Queue.status(channel, queue)
    AMQP.Channel.close(channel)

    state
  end

  @doc """
  Returns a list that contains the queue and its subqueue.
  """
  @spec queue_with_subqueues(String.t) :: [String.t]
  def queue_with_subqueues(work_queue) do
    [work_queue] ++ subqueues(work_queue)
  end

  @doc """
  Returns all subqueues for the work queue.
  """
  @spec subqueues(String.t) :: [String.t]
  def subqueues(work_queue) do
    [
      retry_queue(work_queue),
      rejected_queue(work_queue),
      scheduled_queue(work_queue)
    ]
  end

  @doc """
  Returns a name of retry queue.
  """
  @spec retry_queue(String.t) :: String.t
  def retry_queue(work_queue) do
    work_queue <> ".retry"
  end

  @doc """
  Returns a name of rejected queue.
  """
  @spec rejected_queue(String.t) :: String.t
  def rejected_queue(work_queue) do
    work_queue <> ".rejected"
  end

  @doc """
  Returns a name of scheduled queue.
  """
  @spec scheduled_queue(String.t) :: String.t
  def scheduled_queue(work_queue) do
    work_queue <> ".scheduled"
  end
end
