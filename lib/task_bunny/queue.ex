defmodule TaskBunny.Queue do
  defp open(host, queue) do
    {:ok, connection} = AMQP.Connection.open TaskBunny.Host.connect_options(host)
    {:ok, channel} = AMQP.Channel.open(connection)

    AMQP.Queue.declare(channel, queue, durable: true)

    {:ok, connection, channel}
  end

  defp open(queue), do: open(:default, queue)

  def push(host, job, payload) do
    {:ok, connection, channel} = open(host, job)

    queue = job
    exchange = ""
    message = Poison.encode!(payload)

    publish_state = AMQP.Basic.publish(channel, exchange, queue, message, persistent: true)

    AMQP.Connection.close(connection)

    publish_state
  end

  def push(job, payload), do: push(:default, job, payload)

  def state(host, queue) do
    {:ok, connection, channel} = open(host, queue)

    {:ok, state} = AMQP.Queue.declare(channel, queue, durable: true)

    AMQP.Connection.close(connection)

    state
  end

  def state(queue), do: state(:default, queue)

  def purge(host, queue) do
    {:ok, connection, channel} = open(host, queue)

    AMQP.Queue.purge(channel, queue)

    AMQP.Connection.close(connection)

    :ok
  end

  def purge(queue), do: purge(:default, queue)

  def consume(host, queue, concurrency) do
    {:ok, connection, channel} = open(host, queue)

    :ok = AMQP.Basic.qos(channel, prefetch_count: concurrency)
    {:ok, consumer_tag} = AMQP.Basic.consume(channel, queue)

    {connection, channel, consumer_tag}
  end

  def consume(queue, concurrency \\ 1), do: consume(:default, queue, concurrency)

  def cancel_consume({connection, channel, consumer_tag}) do
    AMQP.Basic.cancel(channel, consumer_tag)
    AMQP.Channel.close(channel)
    AMQP.Connection.close(connection)
  end

  def ack(channel, %{delivery_tag: tag}, succeeded) do
    if succeeded do
      AMQP.Basic.ack(channel, tag)
    else
      AMQP.Basic.nack(channel, tag)
    end
  end
end
