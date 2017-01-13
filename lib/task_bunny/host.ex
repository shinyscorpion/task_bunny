defmodule TaskBunny.Host do
  @moduledoc ~S"""
  TaskBunny.Host registers hosts with connection options.

  If your application deals with a single RabbitMQ host,
  you don't need to care about the host alias.

    iex> TaskBunny.Host.register host: "localhost", port: 5672
    iex> TaskBunny.Queue.push job, payload

  If your application deals with multiple RabbitMQ hosts,
  you have to specify the host when you access to queue.

    iex> TaskBunny.Host.register host: "localhost", port: 5672
    :default
    iex> TaskBunny.Host.register :bunny, host: "bunny.example.com", port: 5672
    # Enqueue to default host
    iex> TaskBunny.Queue.push job, payload
    # Enqueue to :bunny
    iex> TaskBunny.Queue.push :bunny, other_job, payload

  """

  @table :task_bunny_hosts

  @doc ~S"""
  Registers a host to TaskBunny and store the connection options.
  See https://github.com/pma/amqp/blob/master/lib/amqp/connection.ex for the options you can set.

  ## Examples

    iex> TaskBunny.Host.register :host1, host: "localhost", port: 5672
    :host1

    iex> TaskBunny.Queue.push :host1, job, payload
    :ok

  """
  @spec register(host_alias :: atom, connect_options :: list | String.t) :: atom
  def register(host_alias, host_options) do
    ensure_table
    :ets.insert @table, {host_alias, host_options}

    host_alias
  end

  @doc ~S"""
  Registers a host with :default.

  ## Examples

    iex> TaskBunny.Host.register host: "localhost", port: 5672
    :default

    iex> TaskBunny.Queue.push job, payload
    :ok

  """
  @spec register(connect_options :: list | String.t) :: atom
  def register(connect_options), do: register(:default, connect_options)

  @doc """
  Returns connect options for the host
  """
  @spec register(host_alias :: atom) :: list | String.t
  def connect_options(host_alias \\ :default) do
    [{_, options}] = :ets.lookup(@table, host_alias)
    options
  end

  @doc """
  Clear all host information
  """
  @spec clear :: boolean
  def clear do
    if table_exists?, do: :ets.delete @table
  end

  defp table_exists? do
    case :ets.info(@table) do
      :undefined -> false
      _ -> true
    end
  end

  defp ensure_table do
    if !table_exists?, do: :ets.new @table, [:named_table, :public]
  end
end
