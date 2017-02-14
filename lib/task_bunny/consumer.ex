defmodule TaskBunny.Consumer do
  @moduledoc """
  Functions that work on RabbitMQ consumer
  """
  require Logger

  alias AMQP.{Channel, Basic}

  @doc """
  Opens a channel for the given connection and start consuming messages for the queue.
  """
  @spec consume(struct, String.t, integer) :: {struct, String.t} | nil
  def consume(connection, queue, concurrency) do
    case Channel.open(connection) do
      {:ok, channel} ->
        :ok = Basic.qos(channel, prefetch_count: concurrency)
        {:ok, consumer_tag} = Basic.consume(channel, queue)

        {channel, consumer_tag}
      error ->
        Logger.warn "TaskBunny.Consumer: failed to open channel for #{queue}. Detail: #{inspect error}"

        nil
    end
  end

  @doc """
  Acknowledges to the message.
  """
  @spec ack(%Channel{}, map, boolean) :: :ok
  def ack(channel, meta, succeeded)

  def ack(channel, %{delivery_tag: tag}, true), do: Basic.ack(channel, tag)
  def ack(channel, %{delivery_tag: tag}, false) do
    # You have to set false to requeue option to be dead lettered
    Basic.nack(channel, tag, requeue: false)
  end
end
