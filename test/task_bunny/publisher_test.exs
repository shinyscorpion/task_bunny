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
  end
end
