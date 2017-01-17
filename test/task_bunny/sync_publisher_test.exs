defmodule TaskBunny.SyncSyncPublisherTest do
  use ExUnit.Case, async: false

  alias TaskBunny.{
    SyncPublisher,
    TestSupport.QueueHelper,
  }

  @queue_name "test.SyncPublishertest"

  setup do
    QueueHelper.purge @queue_name

    on_exit fn ->
      QueueHelper.purge @queue_name
    end

    :ok
  end

  describe "push" do
    test "queues a job" do
      assert SyncPublisher.push(@queue_name, "Do this") == :ok
    end

    test "queued job exists" do
      SyncPublisher.push(@queue_name, "Do this")

      {payload, _} = QueueHelper.pop @queue_name

      assert payload == "\"Do this\""
    end
  end

  describe "SyncPublisher connection" do
    test "reconnects" do
      SyncPublisher.push(@queue_name, "Do this")

      {payload_do_this, _} = QueueHelper.pop @queue_name

      # Simulate connection closure
      AMQP.Connection.close(TaskBunny.Connection.open(:default))

      # Now send the message again
      QueueHelper.push_when_server_back(@queue_name, "Also do this")

      {payload_also_do_this, _} = QueueHelper.pop @queue_name

      # Check to see if both payloads match (before and after the connection going own.)
      assert payload_do_this == "\"Do this\""
      assert payload_also_do_this == "\"Also do this\""
    end
  end
end
