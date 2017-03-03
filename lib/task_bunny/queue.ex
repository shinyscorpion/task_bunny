defmodule TaskBunny.Queue do
  @doc """
  Conviniences for accessing TaskBunny queues.

  When you have a worker queue called "task_bunny", TaskBunny defines the following sub queues with it.

  - task_bunny.retry: queues for retry
  - task_bunny.rejected: queues for rejected message (failed more than max retries or wrong message format)
  """

  @spec declare_with_subqueues(%AMQP.Connection{} | atom, String.t) :: {map, map, map}
  def declare_with_subqueues(host, work_queue) when is_atom(host) do
    conn = TaskBunny.Connection.get_connection!(host)
    declare_with_subqueues(conn, work_queue)
  end

  def declare_with_subqueues(connection, work_queue) do
    {:ok, channel} = AMQP.Channel.open(connection)

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

    AMQP.Channel.close(channel)

    {work, retry, rejected}
  end

  @spec delete_with_subqueues(%AMQP.Connection{} | atom, String.t) :: :ok
  def delete_with_subqueues(host, work_queue) when is_atom(host) do
    conn = TaskBunny.Connection.get_connection(host)
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

  @spec declare(%AMQP.Channel{}, String.t, keyword) :: map
  def declare(channel, queue, options \\ []) do
    options = options ++ [durable: true]
    {:ok, state} = AMQP.Queue.declare(channel, queue, options)

    state
  end

  @spec state(%AMQP.Connection{}, String.t) :: map
  def state(connection, queue) do
    {:ok, channel} = AMQP.Channel.open(connection)
    {:ok, state} = AMQP.Queue.status(channel, queue)
    AMQP.Channel.close(channel)

    state
  end

  @doc """
  Returns a list that contains the queue and its subqueue
  """
  @spec queue_with_subqueues(String.t) :: [String.t]
  def queue_with_subqueues(work_queue) do
    [work_queue] ++ subqueues(work_queue)
  end

  @doc """
  Returns all sub queues for the work queue.
  """
  @spec subqueues(String.t) :: [String.t]
  def subqueues(work_queue) do
    [
      retry_queue(work_queue),
      rejected_queue(work_queue)
    ]
  end

  @spec retry_queue(String.t) :: String.t
  def retry_queue(work_queue) do
    work_queue <> ".retry"
  end

  @spec rejected_queue(String.t) :: String.t
  def rejected_queue(work_queue) do
    work_queue <> ".rejected"
  end
end
