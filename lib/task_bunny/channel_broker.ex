defmodule TaskBunny.ChannelBroker do
  @moduledoc ~S"""
  Should be replaced, see: [Ticket SEMV2-20](https://onlinedev.atlassian.net/browse/SEMV2-20).
  """

  use GenServer

  require Logger

  # @typedoc ~S"""
  # {consumer process id, queue name}
  # """
  # @typespec consumer_queue :: {pid, String.t}

  # @typedoc ~S"""
  # {channel, concurrency, consumer_tag}
  # """
  # @typespec consumer_data :: {channel, integer, String.t}

  # @typedoc ~S"""
  # list of consumer_queue, consumer_data}
  # """
  # @typespec consumers :: list({consumer_queue, consumer_data})

  # API

  def subscribe(host, queue, concurrency) do
    {:ok, pid} = open_channel_broker(host)

    Process.link(pid) # Link worker to consumer, so when consumers goes down all workers go down too.

    GenServer.call(pid, {:subscribe, {queue, concurrency}})
  end

  def subscribe(queue, concurrency \\ 1), do: subscribe(:default, queue, concurrency)

  def ack(host, queue, tag, succeeded) do
    Logger.info "TaskBunny.ChannelBroker.#{host}: Trying to send ack"
    {:ok, pid} = open_channel_broker(host)

    GenServer.call(pid, {:ack, {queue, tag, succeeded}}, :infinity)
  end

  def ack(queue, tag, succeeded), do: ack(:default, queue, tag, succeeded)

  # Callbacks

  def init([host: host]) do
    TaskBunny.Connection.subscribe()

    {:ok, {host, :no_connection, []}}
  end

  def handle_call({:subscribe, {queue, concurrency}}, {consumer_pid, _}, state) do
    consumer_queue = {consumer_pid, queue}

    case create_consumer(state, consumer_queue, concurrency) do
      {:ok, data} ->
        Logger.info "TaskBunny.ChannelBroker.*: Adding new consumer"
        state = set_data_for_consumer_queue_in_state(consumer_queue, data, state)

        {:reply, :ok, state}
      {:failed, data} ->
        Logger.warn "TaskBunny.ChannelBroker.*: Adding new consumer, but could not open channel"
        state = set_data_for_consumer_queue_in_state(consumer_queue, data, state)

        {:reply, :ok, state}
      error ->
        Logger.error "TaskBunny.ChannelBroker.*: Failed to add new consumer #{inspect(error)}"
        state = set_data_for_consumer_queue_in_state(consumer_queue, {nil, concurrency, nil}, state)

        {:reply, :ok, state}
    end
  end

  def handle_call({:ack, {queue, tag, succeeded}}, {consumer_pid, _}, state = {host, _, _}) do
    Logger.debug "TaskBunny.ChannelBroker.#{host}: Handling to send ack #{inspect(state)}"
    consumer_queue = {consumer_pid, queue}

    case get_data_for_consumer_queue_from_state(consumer_queue, state) do
      {channel, _, _} ->
        result = send_ack(channel, tag, succeeded)

        {:reply, result, state}
      _ ->
        {:reply, :unknown_consumer, state}
    end
  end

  def handle_info(:no_connection, {host, _, data}) do
    Logger.info "TaskBunny.ChannelBroker.#{host}: Lost Connection"

    {:noreply, {host, :no_connection, close_consumer_channels(data)}}
  end

  def handle_info({:connection, connection}, {host, _, data}) do
    Logger.info "TaskBunny.ChannelBroker.#{host}: New connection #{inspect(connection)}"

    {:noreply, reconnect_consumers({host, connection, data})}
  end

  # Helpers

  defp to_process_name_atom(value) do
    value
    |> Atom.to_string
    |> (fn n -> "taskbunny.channelbroker.#{n}" end).()
    |> String.to_atom
  end

  def channel_broker_pid(host) do
    host |> to_process_name_atom |> Process.whereis
  end

  defp open_channel_broker(host) do
    case channel_broker_pid(host) do
      nil ->
        hostname = to_process_name_atom(host)

        GenServer.start_link(__MODULE__, [host: host], [name: hostname])
      pid ->
        {:ok, pid}
    end
  end

  defp send_ack(channel, %{delivery_tag: tag}, succeeded) do
    if succeeded do
      Logger.info "TaskBunny.ChannelBroker: Sending ack for #{inspect(tag)}"
      AMQP.Basic.ack(channel, tag)
    else
      Logger.info "TaskBunny.ChannelBroker: Sending nack for #{inspect(tag)}"
      AMQP.Basic.nack(channel, tag)
    end
  end

  defp create_consumer(state = {_, connection, _}, consumer_queue, concurrency) do
    case get_data_for_consumer_queue_from_state(consumer_queue, state) do
      nil -> open_channel(connection, consumer_queue, concurrency)
      _ -> :channel_allready_created
    end
  end

  defp get_data_for_consumer_queue_from_state(consumer_queue, {_, _, consumers}) do
    case List.keyfind(consumers, consumer_queue, 0) do
      nil -> nil
      {_, data} -> data
    end
  end

  defp set_data_for_consumer_queue_in_state(consumer_queue, data, {host, connection, consumers}) do
    consumers = List.keystore(consumers, consumer_queue, 0, {consumer_queue, data})

    {host, connection, consumers}
  end

  defp close_consumer_channels(consumers) do
    consumer_closer = fn {consumer_queue, {_, concurrency, _}} -> {consumer_queue, {:no_channel, concurrency, :no_tag}} end

    Enum.map(consumers, consumer_closer)
  end

  defp reconnect_consumer(connection, {consumer_queue, {old_channel, concurrency, _}}) do
    Logger.info "Reconnect worker"
    try do
      AMQP.Channel.close(old_channel)
    catch
      _, _ -> :ok
    end

    {_, data} = open_channel(connection, consumer_queue, concurrency)

    {consumer_queue, data}
  end

  defp reconnect_consumers({host, connection, consumers}) do
    consumer_reconnector = fn consumer -> reconnect_consumer(connection,consumer) end

    consumers = Enum.map(consumers, consumer_reconnector)

    {host, connection, consumers}
  end

  defp open_channel(:no_connection, _consumer_queue, concurrency) do
    {:failed, {:no_channel, concurrency, :no_tag}}
  end

  defp open_channel(connection, {consumer_pid, queue}, concurrency) do
    try do
      case AMQP.Channel.open(connection) do
        {:ok, channel} ->
          AMQP.Queue.declare(channel, queue, durable: true)
          :ok = AMQP.Basic.qos(channel, prefetch_count: concurrency)
          {:ok, consumer_tag} = AMQP.Basic.consume(channel, queue, consumer_pid)

          Logger.info "Worker reconnected"
          {:ok, {channel, concurrency, consumer_tag}}
        _ ->
          {:failed, {:no_channel, concurrency, :no_tag}}
      end
    catch
      error_type, error_message ->
        Logger.warn "Channel open #{inspect(error_type)} - #{inspect(error_message)}"

        case TaskBunny.Connection.open() do
          :no_connection -> {:failed, {:no_channel, concurrency, :no_tag}}
          connection -> open_channel(connection, {consumer_pid, queue}, concurrency)
        end
    end
  end
end