defmodule TaskBunny.Consumer do
  @moduledoc """
  Functions that work on RabbitMQ consumer
  """
  require Logger

  @doc """
  Opens a channel for the given connection and start consuming messages for the queue.
  """
  @spec consume(struct, String.t, integer) :: {struct, String.t} | nil
  # TODO: returns tuple
  def consume(connection, queue, concurrency) do
    case AMQP.Channel.open(connection) do
      {:ok, channel} ->
        :ok = AMQP.Basic.qos(channel, prefetch_count: concurrency)
        {:ok, consumer_tag} = AMQP.Basic.consume(channel, queue)

        {channel, consumer_tag}
      error ->
        Logger.warn "TaskBunny.Consumer: failed to open channel for #{queue}. Detail: #{inspect error}"

        nil
    end
  end

  @doc """
  Cancel consumer to stop receiving messages.
  """
  @spec cancel(AMQP.Channel.t, String.t) :: {:ok, String.t}
  def cancel(channel, consumer_tag) do
    AMQP.Basic.cancel(channel, consumer_tag)
  end

  @doc """
  Acknowledges to the message.
  """
  @spec ack(%AMQP.Channel{}, map, boolean) :: :ok
  def ack(channel, meta, succeeded)

  def ack(channel, %{delivery_tag: tag}, true), do: AMQP.Basic.ack(channel, tag)
  def ack(channel, %{delivery_tag: tag}, false) do
    # You have to set false to requeue option to be dead lettered
    AMQP.Basic.nack(channel, tag, requeue: false)
  end
end
