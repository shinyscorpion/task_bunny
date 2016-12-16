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

  describe "queue state" do
    test "contains correct message count" do
      BackgroundQueue.push @test_job_queue, "Do this"
      BackgroundQueue.push @test_job_queue, "Do that"

    
      %{message_count: count} = BackgroundQueue.state @test_job_queue

      assert count == 2
    end

    defp spawn_listener(queue, test_pid) do
      spawn fn -> 
        BackgroundQueue.listen(queue, fn payload ->
          # IO.puts "Listener <#{queue}>: #{payload}"
          send test_pid, :receive_payload
          :ok
        end)
      end
    end

    test "contains correct amount of listeners when listeners > 0" do
      BackgroundQueue.push @test_job_queue, "I am listening to queue"

      listener_pid = spawn_listener(@test_job_queue, self())

      Process.unlink(listener_pid)

      receive do
        :receive_payload -> :ok
      end

      %{consumer_count: count} = BackgroundQueue.state @test_job_queue

      Process.exit(listener_pid, :normal)

      assert count == 1
    end

    test "contains correct amount of listeners when no one is listening" do
      %{consumer_count: count} = BackgroundQueue.state @test_job_queue

      assert count == 0
    end
  end
end