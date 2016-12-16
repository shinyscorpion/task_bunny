defmodule TaskBunny.QueueHelper do
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
end