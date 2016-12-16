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

  def listen(queue, callback) do
    {:ok, connection, channel} = open(queue)

    AMQP.Basic.qos(channel, prefetch_count: 1)
    AMQP.Basic.consume(channel, queue)

    listen(callback, connection, channel)
  end
  
  def listen(callback, connection, channel) do
    {payload, meta} = receive do
      {:basic_deliver, payload, meta} -> {payload, meta}
    end
    
    case callback.(Poison.decode!(payload)) do
      :ok -> 
        AMQP.Basic.ack(channel, meta.delivery_tag)
        listen(callback, connection, channel)
      _ ->
        AMQP.Connection.close(connection)
    end
  end
end