defmodule TaskBunny.BackgroundQueue do
  defp open(queue) do
    {:ok, connection} = AMQP.Connection.open
    {:ok, channel} = AMQP.Channel.open(connection)

    AMQP.Queue.declare(channel, queue, durable: true)
    
    {:ok, connection, channel}
  end

  def push(job, payload) do
    {:ok, connection, channel} = open(job)

    queue = job
    exchange = ""
    message = Poison.encode!(payload)

    publish_state = AMQP.Basic.publish(channel, exchange, queue, message, persistent: true)

    AMQP.Connection.close(connection)

    publish_state
  end

  def state(queue) do
    {:ok, connection, channel} = open(queue)

    {:ok, state} = AMQP.Queue.declare(channel, queue, durable: true)

    AMQP.Connection.close(connection)

    state
  end

  def consume(queue, concurrency \\ 1) do
    {:ok, connection, channel} = open(queue)

    :ok = AMQP.Basic.qos(channel, prefetch_count: concurrency)
    {:ok, consumer_tag} = AMQP.Basic.consume(channel, queue)

    {connection, channel, consumer_tag}
  end

  def cancel_consume({connection, channel, consumer_tag}) do
    AMQP.Basic.cancel(channel, consumer_tag)
    AMQP.Channel.close(channel)
    AMQP.Connection.close(connection)
  end

  def ack(channel, %{deliver_tag: tag}, succeeded) do
    if succeeded do
      AMQP.Basic.ack(channel, tag)
    else
      AMQP.Basic.nack(channel, tag)
    end
  end
end
