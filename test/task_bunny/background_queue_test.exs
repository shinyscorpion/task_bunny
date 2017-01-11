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

  test "consumes a job" do
    consumer_info = BackgroundQueue.consume @test_job_queue

    assert_receive {:basic_consume_ok, _tag}
    BackgroundQueue.push @test_job_queue, "Do this"
    assert_receive {:basic_deliver, "\"Do this\"", _meta}

    BackgroundQueue.cancel_consume consumer_info
  end

  describe "queue state" do
    test "contains correct message count" do
      BackgroundQueue.push @test_job_queue, "Do this"
      BackgroundQueue.push @test_job_queue, "Do that"

      %{message_count: count} = BackgroundQueue.state @test_job_queue

      assert count == 2
    end

    test "contains correct amount of listeners when listeners > 0" do
      consumer_info = BackgroundQueue.consume @test_job_queue

      %{consumer_count: count} = BackgroundQueue.state @test_job_queue

      BackgroundQueue.cancel_consume consumer_info

      assert count == 1
    end

    test "contains correct amount of listeners when no one is listening" do
      %{consumer_count: count} = BackgroundQueue.state @test_job_queue

      assert count == 0
    end
  end
end
