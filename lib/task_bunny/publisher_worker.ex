defmodule TaskBunny.PublisherWorker do
  @moduledoc """
    GenServer worker to publish a message on a queue
  """

  use GenServer

  @doc """
    Starts the publisher
  """
  @spec start_link(list) :: GenServer.on_start()
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, [])
  end

  @doc """
    Initializes the GenServer
  """
  @spec init(any) :: {:ok, map}
  def init(_) do
    {:ok, %{}}
  end

  @doc """
    Attempt to get a channel for the current connection and publish the message on the specified queue
  """
  @spec handle_call({:publish, atom, String.t(), String.t(), String.t(), list}, any, map) ::
          {:reply, :ok, map}
  def handle_call({:publish, host, exchange, routing_key, message, options}, _from, state) do
    with {:ok, channel, new_state} <- get_channel(host, state) do
      {:reply, AMQP.Basic.publish(channel, exchange, routing_key, message, options), new_state}
    else
      error -> {:reply, error, state}
    end
  end

  @doc """
    Closes the AMQP channels opened to publish
  """
  @spec terminate(any, map) :: :ok
  def terminate(_, state) do
    state |> Map.values() |> Enum.each(&AMQP.Channel.close/1)
  end

  defp get_channel(host, state) do
    if channel = state[host] do
      {:ok, channel, state}
    else
      with {:ok, conn} <- TaskBunny.Connection.get_connection(host),
           {:ok, channel} <- AMQP.Channel.open(conn) do
        {:ok, channel, Map.put(state, host, channel)}
      end
    end
  end
end
