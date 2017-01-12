defmodule TaskBunny.JobWorker do
  alias TaskBunny.BackgroundQueue
  alias TaskBunny.JobRunner

  use GenServer

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init({job, concurrency}) do
    # IO.puts "init worker with #{inspect job} and #{inspect concurrency}"
    {_, channel, _} = BackgroundQueue.consume(job.queue_name, concurrency)

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

    BackgroundQueue.ack(channel, meta, succeeded)

    # TODO: logging error here!

    {:noreply, {channel, job}}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end
