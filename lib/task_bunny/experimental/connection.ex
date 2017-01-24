defmodule TaskBunny.Experimental.Connection do
  use GenServer
  require Logger
  alias TaskBunny.Experimental.Config

  @reconnect_interval 1_000
  @max_retry 10

  def start_link({host}) do
    Logger.info "TaskBunny.Connection: start_link with #{host}"
    GenServer.start_link(__MODULE__, {host}, name: pname(host))
  end

  def get_connection(host) do
    # TODO
  end

  def init({host}) do
    case connect(host) do
      {:ok, connection} ->
        Logger.info "TaskBunny.Connection: connected to #{host}"
        Process.monitor(connection.pid)
        {:ok, {host, connection}}

      error ->
        {:stop, {:connect_error, error}}
    end
  end

  def handle_info({:DOWN, _, :process, _pid, reason}, {host, connection}) do
    Logger.warn "TaskBunny.Connection: disconnected from #{host} - PID: #{inspect self()}"

    {:stop, {:connection_lost, reason}, {host}}
  end

  defp connect(host, retried \\ 0) do
    case do_connect(host) do
      {:ok, connection} -> {:ok, connection}
      error -> retry_connect(host, error, retried)
    end
  end

  defp retry_connect(_host, last_error, retried) when retried > @max_retry, do: last_error

  defp retry_connect(host, last_error, retried) do
    Logger.warn "TaskBunny.Connection: failed to connect to #{host}. Error: #{inspect last_error}. Retrying in #{@reconnect_interval} ms"

    :timer.sleep(@reconnect_interval)
    connect(host, retried + 1)
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
