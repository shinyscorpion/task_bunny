defmodule TaskBunny.QueueTest do
  use ExUnit.Case, async: false
  import TaskBunny.TestSupport.QueueHelper

  alias TaskBunny.Queue

  @test_job_queue "jobs.test"

  defp open(queue) do
    {:ok, connection} = AMQP.Connection.open
    {:ok, channel} = AMQP.Channel.open(connection)

    AMQP.Queue.declare(channel, queue, durable: true)

    {:ok, connection, channel}
  end

  defp pop(queue) do
    {:ok, _, channel} = open(queue)

    AMQP.Basic.qos(channel, prefetch_count: 1)
    AMQP.Basic.consume(channel, queue)

    receive do
      {:basic_deliver, payload, meta} ->
        {payload, meta}
    end
  end

  setup do
    clean ["jobs.test"]

    :ok
  end

  test "queue a job" do
    assert Queue.push(@test_job_queue, "Do this") == :ok
  end

  test "queued job exists" do
    Queue.push(@test_job_queue, "Do this")

     {payload, _} = pop @test_job_queue

     assert payload == "\"Do this\""
  end

  test "consumes a job" do
    consumer_info = Queue.consume @test_job_queue

    assert_receive {:basic_consume_ok, _tag}
    Queue.push @test_job_queue, "Do this"
    assert_receive {:basic_deliver, "\"Do this\"", _meta}

    Queue.cancel_consume consumer_info
  end

  describe "queue state" do
    test "contains correct message count" do
      Queue.push @test_job_queue, "Do this"
      Queue.push @test_job_queue, "Do that"

      %{message_count: count} = Queue.state @test_job_queue

      assert count == 2
    end

    test "contains correct amount of listeners when listeners > 0" do
      consumer_info = Queue.consume @test_job_queue

      %{consumer_count: count} = Queue.state @test_job_queue

      Queue.cancel_consume consumer_info

      assert count == 1
    end

    test "contains correct amount of listeners when no one is listening" do
      %{consumer_count: count} = Queue.state @test_job_queue

      assert count == 0
    end
  end

  describe "ack" do
    def receive_message(ack, channel, consumer_tag) do
      received = receive do
        {:basic_deliver, _, meta} ->
          # Shutdown consumer
          AMQP.Basic.cancel(channel, consumer_tag)
          case ack do
            :ack -> Queue.ack(channel, meta, true)
            :nack -> Queue.ack(channel, meta, false)
            _ -> nil # Ignore
          end
          true
        _ -> false
      end
      if !received, do: receive_message(ack, channel, consumer_tag)
    end

    test "success" do
      {_, channel, consumer_tag} = Queue.consume @test_job_queue

      Queue.push @test_job_queue, "Do this"
      receive_message :ack, channel, consumer_tag

      %{message_count: count} = Queue.state @test_job_queue

      assert count == 0
    end

    test "with failed job" do
      {_, channel, consumer_tag} = Queue.consume @test_job_queue

      Queue.push @test_job_queue, "Do this"

      receive_message :nack, channel, consumer_tag

      %{message_count: count} = Queue.state @test_job_queue

      # RabbitMQ will be enqueueing the job automatically
      assert count == 1
    end

    test "without ack/nack" do
      {connection, channel, consumer_tag} = Queue.consume @test_job_queue

      Queue.push @test_job_queue, "Do this"

      receive_message nil, channel, consumer_tag

      # Close channel before sending ack/nack
      AMQP.Channel.close(channel)
      AMQP.Connection.close(connection)

      %{message_count: count} = Queue.state @test_job_queue

      # RabbitMQ will be enqueueing the job automatically
      assert count == 1
    end
  end
end
