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
  alias TaskBunny.Message

  @typedoc ~S"""
  A AMQP message.
  """
  @type message :: {exchange :: String.t, routing_key :: String.t, message :: String.t, options :: list}

  # Api

  @doc ~S"""
  Push a payload to a queue of job.

  The call is synchronous.
  """
  @spec push(atom, atom | String.t, any) :: :ok | :failed
  def push(host \\ :default, job_or_queue, payload_or_message)

  def push(host, job, payload) when is_atom(job) do
    queue = job.queue_name()
    exchange = ""
    routing_key = queue
    message = Message.encode(job, payload)
    options = [persistent: true]

    connection = TaskBunny.Connection.get_connection(host)
    job.declare_queue(connection)

    do_push({exchange, routing_key, message, options}, connection)
  end

  def push(host, queue, message) do
    exchange = ""
    routing_key = queue
    options = [persistent: true]

    connection = TaskBunny.Connection.get_connection(host)

    do_push({exchange, routing_key, message, options}, connection)
  end

  # Helpers
  @spec do_push(message, AMQP.Connection.t | nil) :: :ok | :failed
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
