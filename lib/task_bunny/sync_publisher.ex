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
  Push a given payload for a given job to a given host.

  The call is synchronous.
  """
  @spec push(host :: atom, job :: atom, payload :: any) :: :ok | :failed
  def push(host, job, payload) do
    queue = job
    exchange = ""
    routing_key = queue
    message = Poison.encode!(payload)
    options = [persistent: true]

    connection = TaskBunny.Connection.open(host)

    do_push({queue, exchange, routing_key, message, options}, connection)
  end

  @doc ~S"""
  Push a given payload for a given job to the default (`:default`) host.

  For more info see: [`push/3`](file:///Users/ianlu/projects/square/elixir/onlinedev-task-bunny/doc/TaskBunny.SyncPublisher.html#push/3).
  """
  @spec push(job :: atom, payload :: any) :: :ok | :failed
  def push(job, payload), do: push(:default, job, payload)

  # Helpers

  @spec do_push(item :: message, :no_connection) :: :ok | :failed
  defp do_push(item, :no_connection) do
    Logger.debug "TaskBunny.Publisher: try push but no connection:\r\n    (#{inspect(item)})"
    :failed
  end

  @spec do_push(item :: message, connection :: AMQP.Connection.t) :: :ok | :failed
  defp do_push(item = {queue, exchange, routing_key, payload, options}, connection) do
    try do
      Logger.debug "TaskBunny.Publisher: try push:\r\n    (#{inspect(item)})"
      case AMQP.Channel.open(connection) do
        {:ok, channel} ->
          AMQP.Queue.declare(channel, queue, durable: true)
          AMQP.Basic.publish(channel, exchange, routing_key, payload, options)
          AMQP.Channel.close(channel)

          :ok
        _ ->
          :failed
      end
    catch
      error_type, error_message ->
        Logger.warn "Channel open #{inspect(error_type)} - #{inspect(error_message)}"

        case TaskBunny.Connection.open() do
          :no_connection -> :failed
          connection -> do_push(item, connection)
        end
    end
  end
end