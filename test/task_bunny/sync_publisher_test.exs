defmodule TaskBunny.SyncSyncPublisherTest do
  use ExUnit.Case, async: false
  import TaskBunny.TestSupport.QueueHelper
  alias TaskBunny.{SyncPublisher,TestSupport.QueueHelper}

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

      {payload, _} = QueueHelper.pop(TestJob.queue_name())

      assert payload == "\"Do this\""
    end
  end
end
