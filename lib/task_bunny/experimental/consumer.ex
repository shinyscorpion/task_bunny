defmodule TaskBunny.Experimental.Consumer do
  require Logger

  def consume(nil, queue, concurrency), do: nil

  def consume(connection, queue, concurrency) do
    try do
       open_and_consume(connection, queue, concurrency)

    catch
      error_type, error_message ->
        Logger.warn "Channel open failed for #{queue} queue because of #{inspect error_type} - #{inspect error_message}"
        nil
    end
  end

  defp open_and_consume(connection, queue, concurrency) do
    case AMQP.Channel.open(connection) do
      {:ok, channel} ->
        AMQP.Queue.declare(channel, queue, durable: true)
        :ok = AMQP.Basic.qos(channel, prefetch_count: concurrency)
        {:ok, consumer_tag} = AMQP.Basic.consume(channel, queue)

        {channel, consumer_tag}
      _ ->
        nil
    end
  end

  def ack(channel, %{delivery_tag: tag}, succeeded) do
    if succeeded do
      AMQP.Basic.ack(channel, tag)
    else
      AMQP.Basic.nack(channel, tag)
    end
  end

end
