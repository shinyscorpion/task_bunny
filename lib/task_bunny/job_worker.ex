defmodule TaskBunny.JobWorker do
  alias TaskBunny.BackgroundQueue
  alias TaskBunny.JobRunner

  def start_link({job, concurrency}) do
    {:ok, spawn_link(fn -> init(job, concurrency) end)}
  end

  def init(job, concurrency) do
    {:ok, connection, channel} = BackgroundQueue.open(queue)

    AMQP.Basic.qos(channel, prefetch_count: concurrency)
    AMQP.Basic.consume(channel, queue)

    wait_for_message(connection, channel, job)
  end

  def wait_for_message(connection, channel, job) do
    receive do
      {:basic_deliver, payload, meta} ->
        spawn_job(job, payload, meta)
      {:finish_job, result, meta} ->
        ack_job(job, result, meta)
    end

    wait_for_message(connection, channel, job)
  end

  def spawn_job(job, payload, meta) do
    pid = Spawn(JobRunner, :execute, [])
    send pid, {self, job, payload, meta}
  end

  def ack_job(result, meta) do
    case result do
      :ok ->
        AMQP.Basic.ack(channel, meta.delivery_tag)
      _ ->
        AMQP.Basic.nack(channel, meta.delivery_tag)
    end
  end
end
