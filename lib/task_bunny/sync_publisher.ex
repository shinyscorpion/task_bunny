defmodule TaskBunny.SyncPublisher do
  @moduledoc """
  This module handles pushing to the queue in a synchronous manner.

  ## Examples
  ### Synchronous
      iex> TaskBunny.SynPublisher.push
      %AMQP.Connection{pid: #PID<0.185.0>}


      iex> TaskBunny.Connection.open(:host_down)
      :no_connection


  ### Asynchronous
  #### Default host
      iex>

  #### Specific host
      iex> TaskBunny.Connection.subscribe
      :ok
  """

  require Logger

  @typedoc ~S"""
  A AMQP message.
  """
  @type message :: {queue :: String.t, exchange :: String.t, routing_key :: String.t, message :: String.t, options :: list}

  # Api

  @doc ~S"""
  Push a payload to a queue.

  The call is synchronous.
  """
  @spec push(host :: atom, queue:: atom, payload :: any) :: :ok | :failed
  def push(host, queue, payload) do
    exchange = ""
    routing_key = queue
    message = Poison.encode!(payload)
    options = [persistent: true]

    connection = TaskBunny.Connection.get_connection(host)

    do_push({queue, exchange, routing_key, message, options}, connection)
  end

  @doc ~S"""
  Push a payload to a queue on :default host.

  For more info see: [`push/3`](file:///Users/ianlu/projects/square/elixir/onlinedev-task-bunny/doc/TaskBunny.SyncPublisher.html#push/3).
  """
  @spec push(queue:: atom, payload :: any) :: :ok | :failed
  def push(queue, payload), do: push(:default, queue, payload)

  # Helpers

  @spec do_push(item :: message, nil) :: :ok | :failed
  defp do_push(item, nil) do
    Logger.debug "TaskBunny.Publisher: try push but no connection:\r\n    (#{inspect(item)})"
    :failed
  end

  @spec do_push(item :: message, connection :: AMQP.Connection.t) :: :ok | :failed
  defp do_push(item = {_, exchange, routing_key, payload, options}, connection) do
    try do
      Logger.debug "TaskBunny.Publisher: try push:\r\n    (#{inspect(item)})"
      {:ok, channel} = AMQP.Channel.open(connection)
      Logger.debug "TaskBunny.Publisher: channel #{inspect channel}"
      :ok = AMQP.Basic.publish(channel, exchange, routing_key, payload, options)
      :ok = AMQP.Channel.close(channel)
    rescue
      e ->
        Logger.warn "TaskBunny.Publisher: failed to push. #{inspect(e)}"
        :failed
    end
  end
end
