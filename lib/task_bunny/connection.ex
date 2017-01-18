defmodule TaskBunny.Connection do
  @moduledoc """
  This module handles connections to RabbitMQ.

  The connection can be opened synchronously and asynchronously.
    - For synchronous use `Connection.open`.
    - For asynchronously user `Connection.subscribe`.

  ## Defaults
  ### @reconnect_timeout
  The timeout in ms before trying to reconnect taken from the `TASKBUNNY_RECONNECT_TIMEOUT` environment variable.

  Default: `1000`ms.

  ## Examples
  ### Synchronous
      iex> TaskBunny.Connection.open
      %AMQP.Connection{pid: #PID<0.185.0>}


      iex> TaskBunny.Connection.open(:host_down)
      :no_connection


  ### Asynchronous
  #### Receiver GenServer
      defmodule Receiver do
        use GenServer

        def init(state) do
          \# Start receiving the connection (and connection updates)
          TaskBunny.Connection.subscribe

          {:ok, state}
        end

        def handle_info(:no_connection, state) do
          \# Connection down
          {:noreply, state}
        end

        def handle_info({:connection, connection}, state) do
          \# Connection up (or reconnected)
          {:noreply, state}
        end
      end

  #### Start receiving (same process as receiver GenServer)
      iex> TaskBunny.Connection.subscribe
      :ok
  """

  use GenServer

  require Logger

  alias TaskBunny.{
    Connection,
    Connection.NotificationHelper,
  }

  # Timeout before the GenServer tries to reconnect
  @reconnect_timeout System.get_env("TASKBUNNY_RECONNECT_TIMEOUT") || 1000

  @typedoc ~S"""
  The state of the AMQP connection.
  """
  @type state :: AMQP.Connection.t | :no_connection

  @typedoc ~S"""
  The state of the Connection GenServer.

  Contains:
    - `host`, the host to connect to.
    - `connection`, the state of the AMQP connection.
    - `subscribers`, a list of subcribers (pid).
  """
  @type t ::%__MODULE__{host: atom, connection: state, subscribers: list(pid)}

  @doc ~S"""
  The state of the Connection GenServer.

  Contains:
    - `host`, the host to connect to.
    - `connection`, the state of the AMQP connection.
    - `subscribers`, a list of subcribers (pid).
  """
  defstruct host: :default, connection: :no_connection, subscribers: []

  # API

  @doc ~S"""
  Opens a connections to a given host and returns the AMQP connection state.

  The call is synchronous.
  """
  @spec open(host :: atom) :: state
  def open(host \\ :default) do
    {:ok, pid} = open_connection_server(host)

    GenServer.call(pid, :connection)
  end

  @doc ~S"""
  Closes the connection to a given host.
  """
  @spec close(host :: atom) :: :ok
  def close(host \\ :default) do
    pid = connection_pid(host)

    if pid != nil, do: GenServer.stop(pid)

    :ok
  end

  @doc ~S"""
  Subscribes the current process to a connection for a given host.

  The subscriber will receive the following process messages:
    - `{:connection, connection}`, when a new connection gets made.
    - `:no_connection`, on connection loss.

  This call is asynchronous.

  The subscriber will immediately receive a `{:connection, connection}` if a connection is available.
  In the case of `:no_connection` the subscriber will not be notified, until the first connection has been made.
  """
  @spec subscribe(host :: atom) :: :ok
  def subscribe(host \\ :default) do
    {:ok, pid} = open_connection_server(host)

    GenServer.cast(pid, {:add_subscriber, self()})
  end

  # Callbacks

  @spec init(list) :: {:ok, Connection.t}
  def init([host: host]) do
    Process.flag(:trap_exit, true)

    {:ok, %Connection{host: host, connection: connect(host)}}
  end

  @spec terminate(reason :: any, state :: Connection.t) :: :normal
  def terminate(reason, %Connection{host: host, connection: connection}) do
    if connection != :no_connection do
      Logger.info "TaskBunny.Connection.#{host}: close connection due to #{inspect(reason)}"
      AMQP.Connection.close(connection)
    end

    :normal
  end

  @spec handle_cast({:add_subscriber, pid}, state :: Connection.t) :: {:noreply, Connection.t}
  def handle_cast({:add_subscriber, subscriber}, state) do
    cond do
      Enum.member?(state.subscribers, subscriber) ->
        {:noreply, state}
      true ->
        NotificationHelper.new_subscriber(state.connection, subscriber)

        {:noreply, %{state | subscribers: [subscriber | state.subscribers]}}
    end
  end

  @spec handle_call(:connection, pid, state :: Connection.t) :: {:reply, state, Connection.t}
  def handle_call(:connection, _from, state) do
    {:reply, state.connection, state}
  end

  @spec handle_call(:close_connection, pid, state :: Connection.t) :: {:reply, state, Connection.t}
  def handle_call(:close_connection, _from, state) do
    NotificationHelper.connection_down(state.subscribers)

    {:reply, state.connection, %{state | connection: :no_connection}}
  end

  @spec handle_info({:DOWN, any, :process, pid, any}, Connection.t) :: {:noreply, Connection.t}
  def handle_info({:DOWN, _, :process, _pid, _reason}, state) do
    Logger.warn "TaskBunny.Connection.#{state.host}: connection went down (#{state.host})"

    NotificationHelper.connection_down(state.subscribers)

    Process.send_after(self(), :reconnect, @reconnect_timeout)

    {:noreply, %{state | connection: :no_connection}}
  end

  @spec handle_info(:reconnect, Connection.t) :: {:noreply, Connection.t}
  def handle_info(:reconnect, state) do
    Logger.debug "TaskBunny.Connection.#{state.host}: try reconnect to #{state.host}"

    case connect(state.host) do
      :no_connection ->
        {:noreply, %{state | connection: :no_connection}}
      connection ->
        NotificationHelper.connection_up(connection, state.subscribers)
        {:noreply, %{state | connection: connection}}
    end
  end

  # Helpers
  @spec to_process_name_atom(value :: atom) :: atom
  defp to_process_name_atom(value) do
    value
    |> Atom.to_string
    |> (fn n -> "TaskBunny.Connection.#{n}" end).()
    |> String.to_atom
  end

  @spec connection_pid(host :: atom) :: pid | nil
  defp connection_pid(host) do
    host |> to_process_name_atom |> Process.whereis
  end

  @spec open_connection_server(host :: atom) :: {atom, pid}
  defp open_connection_server(host) do
    case connection_pid(host) do
      nil ->
        hostname = to_process_name_atom(host)
        Logger.info "TaskBunny.Connection.#{host}: #{hostname} not found creating new connection"

        {result, pid} = GenServer.start_link(__MODULE__, [host: host], [name: hostname])

        if result == :ok, do: Process.unlink(pid)

        {result, pid}
      pid ->
        {:ok, pid}
    end
  end

  @spec connect(host :: atom) :: state
  defp connect(host) do
    case AMQP.Connection.open TaskBunny.Host.connect_options(host) do
      {:ok, connection} ->
        Process.monitor(connection.pid)

        Logger.info "TaskBunny.Connection.#{host}: connected to #{host}"

        connection
      {:error, _} ->
        Logger.warn "TaskBunny.Connection.#{host}: failed to connect to #{host}, retry in #{@reconnect_timeout}ms"
        Process.send_after(self(), :reconnect, @reconnect_timeout)

        :no_connection
    end
  end
end