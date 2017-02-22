defmodule TaskBunny.Queue do
  @moduledoc false

  @spec declare_with_retry(%AMQP.Connection{} | atom, String.t) :: {map, map, map}
  def declare_with_retry(host, queue_name) when is_atom(host) do
    conn = TaskBunny.Connection.get_connection(host)
    declare_with_retry(conn, queue_name)
  end

  def declare_with_retry(connection, queue_name) do
    {:ok, channel} = AMQP.Channel.open(connection)

    retry_queue = retry_queue_name(queue_name)
    rejected_queue = rejected_queue_name(queue_name)

    work = declare(channel, queue_name, [durable: true])
    rejected = declare(channel, rejected_queue, [durable: true])

    # Set main queue as dead letter exchange of retry queue.
    # It will requeue the message once message TTL is over.
    retry_options = [
      arguments: [
        {"x-dead-letter-exchange", :longstr, ""},
        {"x-dead-letter-routing-key", :longstr, queue_name}
      ],
      durable: true
    ]
    retry = declare(channel, retry_queue, retry_options)

    AMQP.Channel.close(channel)

    {work, retry, rejected}
  end

  @spec delete_with_retry(%AMQP.Connection{} | atom, String.t) :: :ok
  def declare_with_retry(host, queue_name) when is_atom(host) do
    conn = TaskBunny.Connection.get_connection(host)
    delete_with_retry(conn, queue_name)
  end

  def delete_with_retry(connection, queue_name) do
    {:ok, channel} = AMQP.Channel.open(connection)

    AMQP.Queue.delete(channel, queue_name)
    AMQP.Queue.delete(channel, retry_queue_name(queue_name))
    AMQP.Queue.delete(channel, rejected_queue_name(queue_name))

    AMQP.Channel.close(channel)
    :ok
  end

  @spec declare(%AMQP.Channel{}, String.t, keyword) :: map
  def declare(channel, queue_name, options \\ []) do
    options = options ++ [durable: true]
    {:ok, state} = AMQP.Queue.declare(channel, queue_name, options)

    state
  end

  @spec state(%AMQP.Connection{}, String.t) :: map
  def state(connection, queue) do
    {:ok, channel} = AMQP.Channel.open(connection)
    {:ok, state} = AMQP.Queue.status(channel, queue)
    AMQP.Channel.close(channel)

    state
  end

  @spec retry_queue_name(String.t) :: String.t
  def retry_queue_name(queue_name) do
    queue_name <> ".retry"
  end

  @spec rejected_queue_name(String.t) :: String.t
  def rejected_queue_name(queue_name) do
    queue_name <> ".rejected"
  end
end
