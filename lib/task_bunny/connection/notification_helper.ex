defmodule TaskBunny.Connection.NotificationHelper do
  @moduledoc """
  This helper module handles notifcations for the [`TaskBunny.Connection`](TaskBunny.SyncPublisher.html).
  """

  alias TaskBunny.Connection

  @doc ~S"""
  Notifies the new subscriber pid of the current connection, but only if there is any.
  The subscriber is not notified if the connection is `:no_connection`.
  """
  @spec new_subscriber(connection :: Connection.state, subscriber_pid :: pid) :: nil
  def new_subscriber(connection, subscriber_pid) do
    if connection != :no_connection, do: notify_subscriber({:connection, connection}, subscriber_pid)

    nil
  end

  @doc ~S"""
  Sends the connection down message to all subscribers.

  Returns the list with subscriber pids, where all not-alive pids have been filtered out.
  """
  @spec connection_down(subscribers :: list(pid)) :: list(pid)
  def connection_down(subscribers), do: connection_state(:no_connection, subscribers)

  @doc ~S"""
  Sends the connection up (new connection) message to all subscribers.

  Returns the list with subscriber pids, where all not-alive pids have been filtered out.
  """
  @spec connection_up(connection :: Connection.state, subscribers :: list(pid)) :: list(pid)
  def connection_up(connection, subscribers), do: connection_state({:connection, connection}, subscribers)

  @spec notify_subscriber(state :: Connection.t, subscriber_pid :: pid) :: boolean
  defp notify_subscriber(state, subscriber_pid) do
    alive = Process.alive?(subscriber_pid)

    if alive, do: Process.send(subscriber_pid, state, [])

    alive
  end

  @spec connection_state(state :: Connection.t, subscribers :: list(pid)) :: list(pid)
  defp connection_state(state, subscribers) do
    notifier = fn subscriber -> notify_subscriber(state, subscriber) end

    Enum.filter(subscribers, notifier)
  end
end