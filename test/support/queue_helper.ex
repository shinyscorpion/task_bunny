defmodule TaskBunny.TestSupport.QueueHelper do
  defmacro clean(queues) do
    quote do
      # Remove pre-existing queues before every test.
      {:ok, connection} = AMQP.Connection.open
      {:ok, channel} = AMQP.Channel.open(connection)

      Enum.each(unquote(queues), fn queue -> AMQP.Queue.delete(channel, queue) end)

      on_exit fn ->
        # Cleanup after test by removing queue.
        Enum.each(unquote(queues), fn queue -> AMQP.Queue.delete(channel, queue) end)
        AMQP.Connection.close(connection)
      end
    end
  end

  # Queue Helpers
  def open_channel(queue, host \\ :default) do
    {:ok, connection} = AMQP.Connection.open TaskBunny.Host.connect_options(host)
    {:ok, channel} = AMQP.Channel.open(connection)

    {:ok, state} = AMQP.Queue.declare(channel, queue, durable: true)

    {:ok, connection, channel, state}
  end

  def push_when_server_back(queue, payload, host \\ :default) do
    case TaskBunny.SyncPublisher.push(host, queue, payload) do
      :ok ->
        :ok
      :failed ->
        Process.sleep(100)

        push_when_server_back(queue, payload, host)
    end
  end

  def purge(queue, host \\ :default)

  def purge(queue, host) when is_binary(queue) do
    {:ok, connection, channel, _} = open_channel(queue, host)

    AMQP.Queue.purge(channel, queue)

    AMQP.Connection.close(connection)

    :ok
  end

  def purge(job, host) do
    purge(job.queue_name, host)
  end

  def state(queue, host \\ :default) do
    {:ok, connection, _channel, state} = open_channel(queue, host)

    AMQP.Connection.close(connection)

    state
  end

  def pop(queue) do
    {:ok, _, channel, _} = open_channel(queue)

    AMQP.Basic.qos(channel, prefetch_count: 1)
    AMQP.Basic.consume(channel, queue)

    receive do
      {:basic_deliver, payload, meta} ->
        {payload, meta}
    end
  end

  def receive_message(ack, queue) do
    received =
      receive do
        {:basic_deliver, _, meta} ->
          # Shutdown consumer
          # AMQP.Basic.cancel(channel, consumer_tag)
          case ack do
            :ack -> TaskBunny.ChannelBroker.ack(queue, meta, true)
            :nack -> TaskBunny.ChannelBroker.ack(queue, meta, false)
            _ -> nil # Ignore
          end
          true
        _ -> false
      end

    if !received, do: receive_message(ack, queue)
  end

  def receive_delivery(delivery, queue) do
    received = receive do
      {:basic_deliver, payload, _} -> delivery == payload
      _ -> :wrong_message
    end

    case received do
      :wrong_message -> receive_delivery(delivery, queue)
      result -> result
    end
  end
end