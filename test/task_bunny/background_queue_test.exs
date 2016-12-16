defmodule TaskBunny.BackgroundJobTest do
  use ExUnit.Case, async: false

  import TaskBunny.QueueHelper

  alias TaskBunny.BackgroundQueue

  @test_job_queue "jobs.test"

  defp open(queue) do
    {:ok, connection} = AMQP.Connection.open
    {:ok, channel} = AMQP.Channel.open(connection)

    AMQP.Queue.declare(channel, queue, durable: true)
    
    {:ok, connection, channel}
  end

  defp pop(queue) do
    {:ok, connection, channel} = open(queue)

    AMQP.Basic.qos(channel, prefetch_count: 1)
    AMQP.Basic.consume(channel, queue)

    receive do
      {:basic_deliver, payload, meta} ->
        {payload, meta}
    end
  end

  setup do
    TaskBunny.QueueHelper.clean(["jobs.test"])
    
    :ok
  end

  test "queue a job" do
    assert BackgroundQueue.push(@test_job_queue, "Do this") == :ok
  end

  test "queued job exists" do
    BackgroundQueue.push(@test_job_queue, "Do this")

     {payload, _} = pop @test_job_queue

     assert payload == "\"Do this\""
  end

  test "dequeue a job" do
    BackgroundQueue.push @test_job_queue, "Do this"
  
    {exit_code, _} =  try do
      task = Task.async(fn ->
        BackgroundQueue.listen(@test_job_queue, fn "Do this" ->
          exit(:normal)
        end)
      end)

      Task.await task, 1000
    catch
      :exit, reason -> reason
    end

    assert exit_code == :normal
  end
end