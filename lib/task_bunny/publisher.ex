defmodule TaskBunny.Publisher do
  @moduledoc """
  Conviniences for publishing messages to a queue.

  It's a semi private module and provides lower level functions.
  You should use Job.enqueue to enqueue a job from your application.
  """
  require Logger
  alias TaskBunny.{Connection.ConnectError, Publisher.PublishError}

  @poolboy_timeout 10_000

  @doc """
  Publish a message to the queue.

  Returns `:ok` when the message has been successfully sent to the server.
  Otherwise returns `{:error, detail}`
  """
  @spec publish(atom, String.t(), String.t(), keyword) :: :ok | {:error, any}
  def publish(host, queue, message, options \\ []) do
    publish!(host, queue, message, options)
  rescue
    e in [ConnectError, PublishError] -> {:error, e}
  end

  @doc """
  Similar to publish/4 but raises exception on error. It calls the publisher worker to publish the
  message on the queue
  """
  @spec publish!(atom, String.t(), String.t(), keyword) :: :ok
  def publish!(host, queue, message, options \\ []) do
    Logger.debug("""
    TaskBunny.Publisher: publish
    #{host}:#{queue}: #{inspect(message)}. options = #{inspect(options)}
    """)

    exchange = ""
    routing_key = queue
    options = Keyword.merge([persistent: true], options)

    case :poolboy.transaction(
           :publisher,
           &GenServer.call(&1, {:publish, host, exchange, routing_key, message, options}),
           @poolboy_timeout
         ) do
      :ok -> :ok
      error -> raise PublishError, inner_error: error
    end
  end

  @spec exchange_publish(atom, String.t(), String.t(), String.t(), keyword) :: :ok | {:error, any}
  def exchange_publish(host, exchange, queue, message, options \\ []) do
    exchange_publish!(host, exchange, queue, message, options)
  rescue
    e in [ConnectError, PublishError] -> {:error, e}
  end

  @spec exchange_publish!(atom, String.t(), String.t(), String.t(), keyword) :: :ok
  def exchange_publish!(host, exchange, queue, message, options \\ []) do
    Logger.debug("""
    TaskBunny.Publisher: publish
    #{host}:#{queue}: #{inspect(message)}. options = #{inspect(options)}
    """)

    options = Keyword.merge([persistent: true], options)

    case :poolboy.transaction(
           :publisher,
           &GenServer.call(&1, {:publish, host, exchange, queue, message, options}),
           @poolboy_timeout
         ) do
      :ok -> :ok
      error -> raise PublishError, inner_error: error
    end
  end
end
