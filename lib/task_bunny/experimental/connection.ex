defmodule TaskBunny.Experimental.Connection do
  use GenServer
  require Logger
  alias TaskBunny.Experimental.Config

  @reconnect_interval 5_000

  def start_link({host, _, _} = state) do
    Logger.info "TaskBunny.Connection: start_link with #{host}"

    GenServer.start_link(__MODULE__, state, name: pname(host))
  end

  def start_link(host) do
    start_link({host, nil, []})
  end

  def get_connection(host) do
    case Process.whereis(pname(host)) do
      nil -> nil
      pid -> GenServer.call(pid, :get_connection)
    end
  end

  def monitor_connection(host, listener_pid) do
    case Process.whereis(pname(host)) do
      nil -> :error
      pid ->
        GenServer.cast(pid, {:monitor_connection, listener_pid})
        :ok
    end
  end

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

  defp notify_connect(connection, listeners) do
    Enum.each listeners, fn (pid) ->
      if Process.alive?(pid), do: send(pid, {:connected, connection})
    end
  end

  defp do_connect(host) do
    try do
      AMQP.Connection.open Config.connect_options(host)
    rescue
      error -> {:error, error}
    end
  end

  defp pname(host) do
    "task_bunny.connection." <> Atom.to_string(host)
    |> String.to_atom
  end
end
