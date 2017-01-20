defmodule TaskBunny.Worker do
  alias TaskBunny.{ChannelBroker, JobRunner}

  use GenServer
  require Logger

  def start_link({job, concurrency}) do
    GenServer.start_link(__MODULE__, {job, concurrency}, name: job)
  end

  def init({job, concurrency}) do
    Logger.info "TaskBunny.Worker initializing with #{inspect job} and maximum #{inspect concurrency} concurrent jobs: PID: #{inspect self()}"
    result = ChannelBroker.subscribe(job.queue_name, concurrency)

    if result != :ok, do: raise "Can not connect to job queue."

    {:ok, {job}}
  end

  def handle_info({:basic_deliver, payload, meta}, {job}) do
    JobRunner.invoke(job, Poison.decode!(payload), meta)

    {:noreply, {job}}
  end

  def handle_info({:job_finished, result, meta}, {job}) do
    succeeded = case result do
      :ok -> true
      {:ok, _} -> true
      _ -> false
    end

    ChannelBroker.ack(job.queue_name, meta, succeeded)

    {:noreply, {job}}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end
