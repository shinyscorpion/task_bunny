defmodule TaskBunny.Initializer do
  # Handles initialization concerns.
  #
  # This module is private to TaskBunny and should not be accessed directly.
  #
  @moduledoc false
  use GenServer
  require Logger
  alias TaskBunny.{Config, Queue}

  @doc false
  @spec start_link(boolean) :: GenServer.on_start()
  def start_link(initialized \\ false) do
    GenServer.start_link(__MODULE__, initialized, name: __MODULE__)
  end

  @doc false
  def init(true) do
    # Already initialized. Nothing to do.
    {:ok, true}
  end

  @doc false
  @spec init(boolean) :: {:ok, boolean}
  def init(false) do
    declare_queues_from_config()
    {:ok, true}
  end

  @doc """
  Returns true if TaskBunny has been initialized
  """
  @spec initialized?() :: boolean
  def initialized? do
    case Process.whereis(__MODULE__) do
      nil -> false
      pid -> GenServer.call(pid, :get_state)
    end
  end

  @doc """
  Returns true if Initializer process exists
  """
  @spec alive?() :: boolean
  def alive? do
    Process.whereis(__MODULE__) != nil
  end

  @doc false
  @spec handle_call(atom, {pid, term}, boolean) :: {:reply, boolean, boolean}
  def handle_call(:get_state, _, state) do
    {:reply, state, state}
  end

  @doc false
  @spec handle_info(any, boolean) :: {:noreply, boolean}
  def handle_info({:connected, _conn}, false) do
    # This is called only on edge case where connection was disconnected.
    # Since the attempt of subscribe_connection is still valid, Connection
    # module will send a message.
    # Try to initialize here.
    declare_queues_from_config()
    {:noreply, true}
  end

  def handle_info({:connected, _conn}, state) do
    {:noreply, state}
  end

  @doc """
  Loads config and declares queues listed
  """
  @spec declare_queues_from_config() :: :ok
  def declare_queues_from_config do
    Config.queues()
    |> Enum.each(fn queue -> declare_queue(queue) end)

    :ok
  end

  @spec declare_queue(map) :: :ok
  defp declare_queue(queue_config) do
    queue = queue_config[:name]
    host = queue_config[:host] || :default

    TaskBunny.Connection.subscribe_connection(host, self())

    receive do
      {:connected, conn} -> declare_queue(conn, queue)
    after
      2_000 ->
        Logger.warn("""
        TaskBunny.Initializer: Failed to get connection for #{host}.
        TaskBunny can't declare the queues but carries on.
        """)
    end

    :ok
  end

  @spec declare_queue(AMQP.Connection.t(), String.t()) :: :ok
  defp declare_queue(conn, queue) do
    Queue.declare_with_subqueues(conn, queue)
    :ok
  catch
    :exit, e ->
      # Handles the error but we carry on...
      # It's highly likely caused by the options on queue declare don't match.
      # We carry on with error log.
      Logger.warn("""
      TaskBunny.Initializer: Failed to declare queue for #{queue}.
      If you have changed the queue configuration, you have to delete the queue and create it again.
      Error: #{inspect(e)}
      """)

      {:error, {:exit, e}}
  end
end
