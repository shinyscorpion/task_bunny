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
  @type message :: {exchange :: String.t, routing_key :: String.t, message :: String.t, options :: list}

  # Api

  @doc ~S"""
  Push a payload to a queue of job.

  The call is synchronous.
  """
  @spec push(host :: atom, job :: atom | String.t, payload :: any) :: :ok | :failed
  def push(host, job, payload)

  def push(host, job, payload) when is_atom(job) do
    queue = job.queue_name()
    exchange = ""
    routing_key = queue
    message = Poison.encode!(payload)
    options = [persistent: true]

    connection = TaskBunny.Connection.get_connection(host)
    job.declare_queue(connection)

    do_push({exchange, routing_key, message, options}, connection)
  end

  @doc ~S"""
  Push a payload to the queue.

  This function doesn't declare the queue and supposes the queue already exists.
  """
  def push(host, queue, payload) do
    exchange = ""
    routing_key = queue
    message = Poison.encode!(payload)
    options = [persistent: true]

    connection = TaskBunny.Connection.get_connection(host)

    do_push({exchange, routing_key, message, options}, connection)
  end

  @doc ~S"""
  Push a payload to a queue on :default host.

  For more info see: [`push/3`](file:///Users/ianlu/projects/square/elixir/onlinedev-task-bunny/doc/TaskBunny.SyncPublisher.html#push/3).
  """
  @spec push(job :: atom | String.t, payload :: any) :: :ok | :failed
  def push(job, payload), do: push(:default, job, payload)

  # Helpers
  @spec do_push(item :: message, connection :: AMQP.Connection.t | nil) :: :ok | :failed
  defp do_push(item, connection)

  defp do_push(item, nil) do
    Logger.debug "TaskBunny.Publisher: try push but no connection:\r\n    (#{inspect(item)})"
    :failed
  end

  defp do_push(item = {exchange, routing_key, payload, options}, connection) do
    Logger.debug "TaskBunny.Publisher: push:\r\n    #{inspect(item)}"
    {:ok, channel} = AMQP.Channel.open(connection)
    :ok = AMQP.Basic.publish(channel, exchange, routing_key, payload, options)
    :ok = AMQP.Channel.close(channel)

    :ok
  rescue
    MatchError -> :failed
  end
end
