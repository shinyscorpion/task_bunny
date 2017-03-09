defmodule TaskBunny.Publisher do
  @moduledoc """
  Conviniences for publishing messages to a queue.

  It provides lower level functions.
  You should use Job.enqueue to enqueue a job from your application.
  """
  require Logger

  @doc """
  Publish a message to the queue.

  Returns `:ok` when the message has been successfully sent to the server.
  Otherwise returns `{:error, detail}`
  """
  @spec publish(atom, String.t, String.t, keyword) :: :ok | {:error, any}
  def publish(host, queue, message, options \\ []) do
    {:ok, conn} = TaskBunny.Connection.get_connection(host)
    exchange = ""
    routing_key = queue
    options = Keyword.merge([persistent: true], options)

    do_publish(conn, exchange, routing_key, message, options)
  end

  # TODO: publish!

  @spec do_publish(AMQP.Connection.t, String.t, String.t, String.t, keyword) :: :ok | {:error, any}
  defp do_publish(nil, _, _, _, _), do: {:error, "Failed to connect to AMQP host"}

  defp do_publish(conn, exchange, routing_key, message, options) do
    Logger.debug "TaskBunny.Publisher: publish:\r\n #{exchange} - #{routing_key}: #{inspect message}. options = #{inspect options}"

    # TODO: returns detail error
    {:ok, channel} = AMQP.Channel.open(conn)
    :ok = AMQP.Basic.publish(channel, exchange, routing_key, message, options)
    :ok = AMQP.Channel.close(channel)
  rescue
    e in MatchError -> {:error, e}
  end
end
