defmodule TaskBunny.Experimental.Connection do
  @moduledoc """
  A GenServer to handle RabbitMQ connection.
  If it fails to connect to the host, it will retry every 5 seconds.

  The module also provides funcitons to access RabbitMQ connections.
  """

  use GenServer
  require Logger
  alias TaskBunny.Experimental.Config

  @reconnect_interval 5_000

  @nodoc
  def start_link({host, _, _} = state) do
    Logger.info "TaskBunny.Connection: start_link with #{host}"

    GenServer.start_link(__MODULE__, state, name: pname(host))
  end

  @doc """
  Starts a GenServer process linked to the cunnrent process.
  """
  @spec start_link(host :: atom) :: GenServer.on_start
  def start_link(host) do
    start_link({host, nil, []})
  end

  @doc """
  Gets a RabbitMQ connection for the given host.
  Returns nil when the connection is not available.
  """
  @spec get_connection(host :: atom) :: struct | nil
  def get_connection(host) do
    case Process.whereis(pname(host)) do
      nil -> nil
      pid -> GenServer.call(pid, :get_connection)
    end
  end

  @doc """
  Asks server to send the connection back asynchronously.
  Once connection has been established, it will send a message with {:connected, connection} to the given process.

  Returns :ok when the server exists.
  Returns :error when the server doesn't exist.
  """
  @spec monitor_connection(host :: atom, listener_pid :: pid) :: :ok | :error
  def monitor_connection(host, listener_pid) do
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
  @spec init({}) :: {:ok, any}
  def init({_, connection, _} = state) do
    if !connection, do: send(self(), :connect)
    {:ok, state}
  end

  def handle_call(:get_connection, _, {_, connection, _} = state) do
    {:reply, connection, state}
  end

  def handle_cast({:monitor_connection, listener}, {host, connection, listeners}) do
    if connection do
      notify_connect(connection, [listener])
      {:noreply, {host, connection, listeners}}
    else
      {:noreply, {host, connection, [listener | listeners]}}
    end
  end

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

  @spec notify_connect(connection :: struct, listeners :: list(pid)) :: :ok
  defp notify_connect(connection, listeners) do
    Enum.each listeners, fn (pid) ->
      if Process.alive?(pid), do: send(pid, {:connected, connection})
    end

    :ok
  end

  @spec do_connect(host :: atom) :: struct | {:error, any}
  defp do_connect(host) do
    try do
      AMQP.Connection.open Config.connect_options(host)
    rescue
      error -> {:error, error}
    end
  end

  @spec pname(host :: atom) :: atom
  defp pname(host) do
    "task_bunny.connection." <> Atom.to_string(host)
    |> String.to_atom
  end
end
