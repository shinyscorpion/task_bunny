defmodule TaskBunny.Experimental.Worker do
  @moduledoc """
  Todo: Add documentation.
  """

  use GenServer
  require Logger
  alias TaskBunny.JobRunner
  alias TaskBunny.Experimental.{Connection,Consumer,Worker}

  defstruct [:job, host: :default, concurrency: 1, channel: nil, consumer_tag: nil]

  def start_link(state = %Worker{}) do

    GenServer.start_link(__MODULE__, state, name: pname(state.job))
  end

  def init(state = %Worker{}) do
    Logger.info "TaskBunny.Worker initializing with #{inspect state.job} and maximum #{inspect state.concurrency} concurrent jobs: PID: #{inspect self()}"
    send(self(), :consume)

    {:ok, state}
  end

  def handle_info(:consume, state = %Worker{}) do
    connection = Connection.get_connection(state.host)

    case Consumer.consume(connection, state.job.queue_name, state.concurrency) do
      {channel, consumer_tag} ->
        Logger.info "TaskBunny.Worker: start consuming #{inspect state.job}. PID: #{inspect self()}"
        {:noreply, %{state | channel: channel, consumer_tag: consumer_tag}}
      _ ->
        Process.send_after(self(), :consume, 500)
        {:noreply, state}
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
