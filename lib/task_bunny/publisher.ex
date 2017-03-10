defmodule TaskBunny.Publisher do
  @moduledoc """
  Conviniences for publishing messages to a queue.

  It provides lower level functions.
  You should use Job.enqueue to enqueue a job from your application.
  """
  require Logger
  alias TaskBunny.{Publisher.PublishError, Connection.ConnectError}

  @doc """
  Publish a message to the queue.

  Returns `:ok` when the message has been successfully sent to the server.
  Otherwise returns `{:error, detail}`
  """
  @spec publish(atom, String.t, String.t, keyword) :: :ok | {:error, any}
  def publish(host, queue, message, options \\ []) do
    publish!(host, queue, message, options)

  rescue
    e in [ConnectError, PublishError] -> {:error, e}
  end

  @doc """
  Similar to publish/4 but raises exception on error.
  """
  @spec publish!(atom, String.t, String.t, keyword) :: :ok
  def publish!(host, queue, message, options \\ []) do
    Logger.debug """
    TaskBunny.Publisher: publish
    #{host}:#{queue}: #{inspect message}. options = #{inspect options}
    """

    conn = TaskBunny.Connection.get_connection!(host)

    exchange = ""
    routing_key = queue
    options = Keyword.merge([persistent: true], options)

    with {:ok, channel} <- AMQP.Channel.open(conn),
         :ok <- AMQP.Basic.publish(channel, exchange, routing_key, message, options),
         :ok <- AMQP.Channel.close(channel)
    do
      :ok
    else
      error -> raise PublishError, error
    end
  end
end
