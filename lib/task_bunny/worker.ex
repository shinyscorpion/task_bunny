defmodule TaskBunny.Worker do
  alias TaskBunny.{Queue, JobRunner}

  use GenServer
  require Logger

  def start_link({job, concurrency}) do
    GenServer.start_link(__MODULE__, {job, concurrency}, name: job)
  end

  def init({job, concurrency}) do
    Logger.info "TaskBunny.Worker initializing with #{inspect job} and maximum #{inspect concurrency} concurrent jobs: PID: #{inspect self()}"
    {_, channel, _} = Queue.consume(job.queue_name, concurrency)

    {:ok, {channel, job}}
  end

  def handle_info({:basic_deliver, payload, meta}, {channel, job}) do
    JobRunner.invoke(job, Poison.decode!(payload), meta)

    {:noreply, {channel, job}}
  end

  def handle_info({:job_finished, result, meta}, {channel, job}) do
    succeeded = case result do
      :ok -> true
      {:ok, _} -> true
      _ -> false
    end

    Queue.ack(channel, meta, succeeded)

    {:noreply, {channel, job}}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end
