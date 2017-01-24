defmodule TaskBunny.Experimental.Connection do
  use GenServer
  require Logger
  alias TaskBunny.Experimental.Config

  @reconnect_interval 5_000

  def start_link({host, connection}) do
    Logger.info "TaskBunny.Connection: start_link with #{host}"
    GenServer.start_link(__MODULE__, {host, connection}, name: pname(host))
  end

  def get_connection(host) do
    case Process.whereis(pname(host)) do
      nil -> nil
      pid -> GenServer.call(pid, :get_connection)
    end
  end

  def init({host, connection}) do
    if !connection, do: send(self(), :connect)
    {:ok, {host, connection}}
  end

  def handle_call(:get_connection, _, {host, connection}) do
    {:reply, connection, {host, connection}}
  end

  def handle_info(:connect, {host, _}) do
    case do_connect(host) do
      {:ok, connection} ->
        Logger.info "TaskBunny.Connection: connected to #{host}"
        Process.monitor(connection.pid)
        {:noreply, {host, connection}}

      error ->
        Logger.warn "TaskBunny.Connection: failed to connect to #{host} - Error: #{inspect error}. Retrying in #{@reconnect_interval} ms"
        Process.send_after(self(), :connect, @reconnect_interval)

        {:noreply, {host, nil}}
    end
  end

  def handle_info({:DOWN, _, :process, _pid, reason}, {host, connection}) do
    Logger.warn "TaskBunny.Connection: disconnected from #{host} - PID: #{inspect self()}"

    {:stop, {:connection_lost, reason}, {host, nil}}
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
