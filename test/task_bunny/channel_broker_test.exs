defmodule TaskBunny.ChannelBrokerTest do
  use ExUnit.Case, async: false

  alias TaskBunny.{
    ChannelBroker,
    SyncPublisher,
    Connection,
    TestSupport.QueueHelper,
  }

  @queue_name "test.channelbroker"

  setup do
    QueueHelper.purge @queue_name

    on_exit fn ->
      QueueHelper.purge @queue_name
    end

    :ok
  end

  describe "subscribe" do
    test "can receive start consume" do
      ChannelBroker.subscribe @queue_name

      assert_receive {:basic_consume_ok, _tag}
    end

    test "can receive job" do
      ChannelBroker.subscribe @queue_name

      SyncPublisher.push @queue_name, "Do this"
      SyncPublisher.push @queue_name, "Do this"

      assert QueueHelper.receive_delivery("\"Do this\"", @queue_name)
    end

    @tag timeout: 15000
    test "can receive job after disconnect" do
      ChannelBroker.subscribe @queue_name

      # Simulate connection closure (need to force channel too?)
      AMQP.Connection.close(TaskBunny.Connection.open(:default))

      # Now publish the job after disconnect
      QueueHelper.push_when_server_back(@queue_name, "Do this")

      assert QueueHelper.receive_delivery("\"Do this\"", @queue_name)
    end
  end

  describe "Sending ack/nack" do
    test "on success" do
      ChannelBroker.subscribe @queue_name

      SyncPublisher.push @queue_name, "Do this"
      QueueHelper.receive_message :ack, @queue_name

      %{message_count: count} = QueueHelper.state @queue_name

      assert count == 0
    end

    test "with failed job" do
      ChannelBroker.subscribe @queue_name

      SyncPublisher.push @queue_name, "Do this"
      QueueHelper.receive_message :nack, @queue_name

      # Close channel before sending ack/nack
      AMQP.Connection.close(Connection.open())

      assert QueueHelper.receive_delivery("\"Do this\"", @queue_name)
    end

    test "without ack/nack" do
      ChannelBroker.subscribe @queue_name, 1

      SyncPublisher.push @queue_name, "Do this"

      QueueHelper.receive_message nil, @queue_name

      # Close channel before sending ack/nack
      AMQP.Connection.close(Connection.open())

      assert QueueHelper.receive_delivery("\"Do this\"", @queue_name)
    end
  end
end