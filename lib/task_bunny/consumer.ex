defmodule TaskBunny.Consumer do
  # Handles consumer concerns.
  #
  # This module is private to TaskBunny and should not be accessed directly.
  #
  @moduledoc false
  require Logger

  @doc """
  Opens a channel and start consuming messages for the queue.
  """
  @spec consume(AMQP.Connection.t(), String.t(), integer) ::
          {:ok, AMQP.Channel.t(), String.t()} | {:error, any}
  def consume(connection, queue, concurrency) do
    with {:ok, channel} <- AMQP.Channel.open(connection),
         :ok <- AMQP.Basic.qos(channel, prefetch_count: concurrency),
         {:ok, consumer_tag} <- AMQP.Basic.consume(channel, queue) do
      {:ok, channel, consumer_tag}
    else
      error ->
        Logger.warn("""
        TaskBunny.Consumer: start consumer for #{queue}.
        Detail: #{inspect(error)}"
        """)

        {:error, error}
    end
  end

  @doc """
  Cancel the consumer to stop receiving messages.
  """
  @spec cancel(AMQP.Channel.t(), String.t()) :: {:ok, String.t()}
  def cancel(channel, consumer_tag) do
    {:ok, _} = AMQP.Basic.cancel(channel, consumer_tag)
  end

  @doc """
  Acknowledges to the message.
  """
  @spec ack(AMQP.Channel.t(), map, boolean) :: :ok
  def ack(channel, meta, succeeded)

  def ack(channel, %{delivery_tag: tag}, true) do
    :ok = AMQP.Basic.ack(channel, tag)
  end

  def ack(channel, %{delivery_tag: tag}, false) do
    # You have to set false to requeue option to be dead lettered
    :ok = AMQP.Basic.nack(channel, tag, requeue: false)
  end
end
