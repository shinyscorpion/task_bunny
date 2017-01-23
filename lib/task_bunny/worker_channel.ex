defmodule TaskBunny.WorkerChannel do
  @moduledoc """
  This module contains the AMQP logic for the worker regarding channels and ack-ing.

  Code needs to replaced by DeadLetterExchange.
  """

  require Logger

  def connect(state) do
    try do
       {channel, consumer_tag} = open_and_consume(state.connection, state.job.queue_name, state.concurrency)

       %{state | channel: channel, consumer_tag: consumer_tag}
    catch
      error_type, error_message ->
        Logger.warn "Channel open failed because of #{inspect error_type} - #{inspect error_message} with state: #{inspect state}"
        state
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
        {nil, nil}
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