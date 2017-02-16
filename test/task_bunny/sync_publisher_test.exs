defmodule TaskBunny.SyncSyncPublisherTest do
  use ExUnit.Case, async: false
  import TaskBunny.TestSupport.QueueHelper
  alias TaskBunny.{SyncPublisher,TestSupport.QueueHelper, Message}

  defmodule TestJob do
    use TaskBunny.Job

    def perform(_payload), do: :ok
  end

  setup do
    clean(TestJob.all_queues())

    :ok
  end

  describe "push" do
    test "queues a job" do
      assert SyncPublisher.push(TestJob, "Do this") == :ok
    end

    test "queued job exists" do
      SyncPublisher.push(TestJob, "Do this")

      {message, _} = QueueHelper.pop(TestJob.queue_name())
      {:ok, %{"payload" => payload}} = Message.decode(message)

      assert payload == "Do this"
    end
  end
end
