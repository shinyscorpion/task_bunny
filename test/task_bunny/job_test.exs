defmodule TaskBunny.JobTest do
  use ExUnit.Case
  import TaskBunny.TestSupport.QueueHelper
  alias TaskBunny.{Job, Queue, Message, TestSupport.QueueHelper}

  @queue "task_bunny.job_test"

  defmodule TestJob do
    use Job
    def perform(_payload), do: :ok
  end

  setup do
    clean(Queue.queue_with_subqueues(@queue))

    :ok
  end

  describe "enqueue" do
    test "enqueues job" do
      payload = %{"foo" => "bar"}
      :ok = TestJob.enqueue(payload, queue: @queue)

      {received, _} = QueueHelper.pop(@queue)
      {:ok, %{"payload" => received_payload}} = Message.decode(received)
      assert received_payload == payload
    end
  end
end
