defmodule TaskBunny.PublisherTest do
  use ExUnit.Case, async: false
  import TaskBunny.QueueTestHelper
  alias TaskBunny.{Publisher, QueueTestHelper}

  @queue_name "task_bunny.test_queue"

  setup do
    clean([@queue_name])
    :ok
  end

  describe "publish" do
    test "publishes a message to a queue" do
      QueueTestHelper.declare(@queue_name)
      Publisher.publish(:default, @queue_name, "Hello Queue")

      {message, _} = QueueTestHelper.pop(@queue_name)
      assert message == "Hello Queue"
    end

    test "returns an error tuple when there is an error" do
      assert Publisher.publish(:invalid, @queue_name, "Hello Queue") ==
               {:error,
                %Publisher.PublishError{
                  inner_error: {:error, :invalid_host},
                  message: "Failed to publish the message.\nerror={:error, :invalid_host}"
                }}
    end
  end

  describe "exchange_publish" do
    test "publishes a message to a queue" do
      QueueTestHelper.declare(@queue_name)
      Publisher.exchange_publish(:default, "", @queue_name, "Hello Queue")

      {message, _} = QueueTestHelper.pop(@queue_name)
      assert message == "Hello Queue"
    end

    test "returns an error tuple when there is an error" do
      assert Publisher.exchange_publish(:invalid, "", @queue_name, "Hello Queue") ==
               {:error,
                %Publisher.PublishError{
                  inner_error: {:error, :invalid_host},
                  message: "Failed to publish the message.\nerror={:error, :invalid_host}"
                }}
    end
  end
end
