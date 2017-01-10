defmodule TaskBunny.JobWorker do
  alias TaskBunny.BackgroundQueue
  alias TaskBunny.JobRunner

  use GenServer

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init({job, concurrency}) do
    channel = BackgroundQueue.consume(job.queue_name, concurrency)

    {:ok, {channel, job}}
  end

  def handle_info({:basic_deliver, payload, meta}, {channel, job}) do
    spawn_job(job, payload, meta)

    {:noreply, {channel, job}}
  end

  def handle_info({:finish_job, result, meta}, {channel, job}) do
    BackgroundQueue.ack(channel, meta, result==:ok)

    {:noreply, {channel, job}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  def spawn_job(job, payload, meta) do
    # TODO
  end
end
