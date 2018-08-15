defmodule TaskBunny.QueueTestHelper do
  defmacro clean(queues) do
    quote do
      # Remove pre-existing queues before every test.
      {:ok, connection} = AMQP.Connection.open()
      {:ok, channel} = AMQP.Channel.open(connection)

      Enum.each(unquote(queues), fn queue -> AMQP.Queue.delete(channel, queue) end)

      on_exit(fn ->
        # Cleanup after test by removing queue.
        Enum.each(unquote(queues), fn queue -> AMQP.Queue.delete(channel, queue) end)
        AMQP.Connection.close(connection)
      end)
    end
  end

  # Queue Helpers
  def open_channel(host \\ :default) do
    conn = TaskBunny.Connection.get_connection!(host)
    {:ok, _channel} = AMQP.Channel.open(conn)
  end

  def declare(queue, host \\ :default) do
    {:ok, channel} = open_channel(host)
    {:ok, _state} = AMQP.Queue.declare(channel, queue, durable: true)

    :ok = AMQP.Channel.close(channel)

    :ok
  end

  def purge(queue, host \\ :default)

  def purge(queue, host) when is_binary(queue) do
    {:ok, channel} = open_channel(host)

    {:ok, _} = AMQP.Queue.purge(channel, queue)
    {:ok, _} = AMQP.Queue.delete(channel, queue)

    :ok = AMQP.Channel.close(channel)

    :ok
  end

  def pop(queue) do
    {:ok, channel} = open_channel()

    :ok = AMQP.Basic.qos(channel, prefetch_count: 1)
    {:ok, _} = AMQP.Basic.consume(channel, queue)

    receive do
      {:basic_deliver, payload, meta} ->
        :ok = AMQP.Channel.close(channel)
        {payload, meta}
    end
  end
end
