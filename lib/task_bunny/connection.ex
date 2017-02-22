defmodule TaskBunny.Connection do
  @moduledoc """
  A GenServer to handle RabbitMQ connection.
  If it fails to connect to the host, it will retry every 5 seconds.

  The module also provides funcitons to access RabbitMQ connections.
  """

  use GenServer
  require Logger
  alias TaskBunny.Config

  @reconnect_interval 5_000

  @type state :: {atom, %AMQP.Connection{} | nil, list(pid)}

  @doc """
  Starts a GenServer process linked to the cunnrent process.
  """
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
  Gets a RabbitMQ connection for the given host.
  Returns nil when the connection is not available.
  """
  @spec get_connection(atom) :: struct | nil
  def get_connection(host \\ :default) do
    case Process.whereis(pname(host)) do
      nil -> nil
      pid -> GenServer.call(pid, :get_connection)
    end
  end

  @doc """
  Similar to `get_connection/1` but raises an error when connection is not ready.
  """
  @spec get_connection!(atom) :: struct
  def get_connection!(host \\ :default) do
    case get_connection(host) do
      nil -> raise "Failed to connect #{host}"
      conn -> conn
    end
  end

  @doc """
  Asks server to send the connection back asynchronously.
  Once connection has been established, it will send a message with {:connected, connection} to the given process.

  Returns :ok when the server exists.
  Returns :error when the server doesn't exist.
  """
  @spec monitor_connection(atom, pid) :: :ok | :error
  def monitor_connection(host \\ :default, listener_pid) do
    case Process.whereis(pname(host)) do
      nil -> :error
      pid ->
        GenServer.cast(pid, {:monitor_connection, listener_pid})
        :ok
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
  def handle_cast({:monitor_connection, listener}, {host, connection, listeners}) do
    if connection do
      notify_connect(connection, [listener])
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
        notify_connect(connection, listeners)

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

  @spec notify_connect(struct, list(pid)) :: :ok
  defp notify_connect(connection, listeners) do
    Logger.debug "TaskBunny.Connection: notifying to #{inspect listeners}"
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
