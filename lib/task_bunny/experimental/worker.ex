defmodule TaskBunny.Experimental.Worker do
  @moduledoc """
  Todo: Add documentation.
  """

  use GenServer
  require Logger
  alias TaskBunny.JobRunner
  alias TaskBunny.Experimental.{Connection,Consumer,Worker}

  defstruct [:job, host: :default, concurrency: 1, channel: nil, consumer_tag: nil]

  def start_link({job, concurrency}) do
    start_link(%Worker{job: job, concurrency: concurrency})
  end

  def start_link({host, job, concurrency}) do
    start_link(%Worker{host: host, job: job, concurrency: concurrency})
  end

  def start_link(state = %Worker{}) do
    GenServer.start_link(__MODULE__, state, name: pname(state.job))
  end

  def init(state = %Worker{}) do
    Logger.info "TaskBunny.Worker initializing with #{inspect state.job} and maximum #{inspect state.concurrency} concurrent jobs: PID: #{inspect self()}"

    case Connection.monitor_connection(state.host, self()) do
      :ok ->
        {:ok, state}
      _ ->
        {:stop, :connection_not_ready}
    end

    {:ok, state}
  end

  def handle_info({:connected, connection}, state = %Worker{}) do
    case Consumer.consume(connection, state.job.queue_name, state.concurrency) do
      {channel, consumer_tag} ->
        Logger.info "TaskBunny.Worker: start consuming #{inspect state.job}. PID: #{inspect self()}"
        {:noreply, %{state | channel: channel, consumer_tag: consumer_tag}}
      error ->
        {:stop, {:failed_to_consume, error}, state}
    end
  end

  def handle_info({:basic_deliver, payload, meta}, state) do
    JobRunner.invoke(state.job, Poison.decode!(payload), meta)

    {:noreply, state}
  end

  def handle_info({:job_finished, result, meta}, state) do
    succeeded = case result do
      :ok -> true
      {:ok, _} -> true
      _ -> false
    end

    Consumer.ack(state.channel, meta, succeeded)

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp pname(job) do
    String.to_atom("TaskBunny.Worker.#{job}")
  end
end
