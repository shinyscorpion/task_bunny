defmodule TaskBunny.Connection do
  @moduledoc """
  A GenServer that handles RabbitMQ connection.
  It provides convenience functions to access RabbitMQ through the GenServer.

  ## GenServer

  TaskBunny loads the configurations and automatically starts a GenServer for each host definition.
  They are supervised by TaskBunny so you don't have to look after them.

  ## Disconnect/Reconnect

  TaskBunny handles disconnection and reconnection.
  Once the GenServer retrieves the RabbitMQ connection the GenServer monitors it.
  When it disconnects or dies the GenServer terminates itself.

  The supervisor restarts the GenServer and it tries to reconnect to the host.
  If it fails to connect, it retries every five seconds.

  ## Access to RabbitMQ connections

  The module provides two ways to retrieve a RabbitMQ connection:

  1. Use `get_connection/1` and it returns the connection synchronously.
  This will succeed in most cases since TaskBunny tries to establish a
  connection as soon as the application starts.

  2. Use `subscribe_connection/1` and it sends the connection back
  asynchronously once the connection is ready.
  This can be useful when you can't ensure the caller might start before the
  connectin is established.

  Check out the function documentation for more details.
  """

  use GenServer
  require Logger
  alias TaskBunny.{Config, Connection.ConnectError}

  @reconnect_interval 5_000

  @typedoc """
  Represents the state of a connection GenServer.

  It's a tuple containing `{host, connection, subscribers}`.
  """
  @type state :: {atom, %AMQP.Connection{} | nil, list(pid)}

  @doc false
  @spec start_link(atom | state) :: GenServer.on_start
  def start_link(host)

  def start_link(state = {host, _, _}) do
    Logger.info "TaskBunny.Connection: start_link with #{host}"

    GenServer.start_link(__MODULE__, state, name: pname(host))
  end

  def start_link(host) do
    start_link({host, nil, []})
  end

  @doc """
  Returns the RabbitMQ connection for the given host.
  When host argument is not passed it returns the connection for the default host.

  ## Examples

      case get_connection() do
        {:ok, conn} -> do_something(conn)
        {:error, _} -> cry()
      end

  """
  @spec get_connection(atom) :: {:ok, AMQP.Connection.t} | {:error, atom}
  def get_connection(host \\ :default) do
    case Process.whereis(pname(host)) do
      nil ->
        case Config.host_config(host) do
          nil -> {:error, :invalid_host}
          _   -> {:error, :no_connection_process}
        end
      pid ->
        case GenServer.call(pid, :get_connection) do
          nil  -> {:error, :not_connected}
          conn -> {:ok, conn}
        end
    end
  end

  @doc """
  Similar to get_connection/1 but raises an exception when connection is not ready.

  ## Examples

      iex> conn = get_connection!()
      %AMQP.Connection{}

  """
  @spec get_connection!(atom) :: AMQP.Connection.t
  def get_connection!(host \\ :default) do
    case get_connection(host) do
      {:ok, conn} -> conn
      {:error, error_type} -> raise ConnectError, type: error_type, host: host
    end
  end

  @doc """
  Requests the GenServer to send the connection back asynchronously.
  Once connection has been established, it will send a message with {:connected, connection} to the given process.

  ## Examples

      :ok = subscribe_connection(self())
      receive do
        {:connected, conn = %AMQP.Connection{}} -> do_something(conn)
      end

  """
  @spec subscribe_connection(atom, pid) :: :ok | {:error, atom}
  def subscribe_connection(host \\ :default, listener_pid) do
    case Process.whereis(pname(host)) do
      nil ->
        case Config.host_config(host) do
          nil -> {:error, :invalid_host}
          _   -> {:error, :no_connection_process}
        end
      pid ->
        GenServer.cast(pid, {:subscribe_connection, listener_pid})
        :ok
    end
  end

  @doc """
  Similar to subscribe_connection/2 but raises an exception when process is not ready.
  ## Examples

      subscribe_connection!(self())
      receive do
        {:connected, conn = %AMQP.Connection{}} -> do_something(conn)
      end

  """
  @spec subscribe_connection!(atom, pid) :: :ok
  def subscribe_connection!(host \\ :default, listener_pid) do
    case subscribe_connection(host, listener_pid) do
      :ok -> :ok
      {:error, error_type} -> raise ConnectError, type: error_type, host: host
    end
  end

  @doc """
  Initialises GenServer. Send a request to establish a connection.
  """
  @spec init(tuple) :: {:ok, any}
  def init(state = {_, connection, _}) do
    if !connection, do: send(self(), :connect)
    {:ok, state}
  end

  @spec handle_call(atom, {pid, term}, state) :: {:reply, %AMQP.Connection{}, state}
  def handle_call(:get_connection, _, state = {_, connection, _}) do
    {:reply, connection, state}
  end

  @spec handle_cast(tuple, state) :: {:noreply, state}
  def handle_cast({:subscribe_connection, listener}, {host, connection, listeners}) do
    if connection do
      publish_connection(connection, [listener])
      {:noreply, {host, connection, listeners}}
    else
      {:noreply, {host, connection, [listener | listeners]}}
    end
  end

  @spec handle_info(any, state) ::
    {:noreply, state} |
    {:stop, reason :: term, state}
  def handle_info(message, state)

  def handle_info(:connect, {host, _, listeners}) do
    case do_connect(host) do
      {:ok, connection} ->
        Logger.info "TaskBunny.Connection: connected to #{host}"
        Process.monitor(connection.pid)
        publish_connection(connection, listeners)

        {:noreply, {host, connection, []}}
      error ->
        Logger.warn "TaskBunny.Connection: failed to connect to #{host} - Error: #{inspect error}. Retrying in #{@reconnect_interval} ms"
        Process.send_after(self(), :connect, @reconnect_interval)

        {:noreply, {host, nil, listeners}}
    end
  end

  def handle_info({:DOWN, _, :process, _pid, reason}, {host, _, _}) do
    Logger.warn "TaskBunny.Connection: disconnected from #{host} - PID: #{inspect self()}"

    {:stop, {:connection_lost, reason}, {host, nil, []}}
  end

  @spec publish_connection(struct, list(pid)) :: :ok
  defp publish_connection(connection, listeners) do
    Enum.each listeners, fn (pid) ->
      if Process.alive?(pid), do: send(pid, {:connected, connection})
    end

    :ok
  end

  @spec do_connect(atom) :: {:ok, %AMQP.Connection{}} | {:error, any}
  defp do_connect(host) do
    AMQP.Connection.open Config.connect_options(host)
  rescue
    error -> {:error, error}
  end

  @spec pname(atom) :: atom
  defp pname(host) do
    "TaskBunny.Connection." <> Atom.to_string(host)
    |> String.to_atom
  end
end
