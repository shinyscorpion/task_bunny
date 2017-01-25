defmodule TaskBunny.WorkerTest do
  use ExUnit.Case, async: false
  import TaskBunny.TestSupport.QueueHelper
  alias TaskBunny.{
    SyncPublisher,
    Connection,
    Worker
  }
  alias TaskBunny.TestSupport.{
    JobTestHelper,
    JobTestHelper.TestJob
  }

  setup do
    clean(TestJob.all_queues())

    JobTestHelper.setup
    TestJob.declare_queue(Connection.get_connection())

    on_exit fn ->
      JobTestHelper.teardown
    end

    :ok
  end

  describe "worker" do
    test "invokes a job with the payload" do
      {:ok, worker} = Worker.start_link({TestJob, 1})
      payload = %{"hello" => "world1"}

      SyncPublisher.push TestJob.queue_name(), payload

      JobTestHelper.wait_for_perform()

      assert List.first(JobTestHelper.performed_payloads) == payload

      GenServer.stop worker
    end

    test "concurrency" do
      {:ok, worker} = Worker.start_link({TestJob, 5})
      payload = %{"sleep" => 10_000}

      # Run 10 jobs and each would take 10 seconds to finish
      Enum.each 1..10, fn (_) ->
        SyncPublisher.push TestJob.queue_name(), payload
      end

      # This waits for up to 1 second
      assert JobTestHelper.wait_for_perform 5

      # Make sure more than specified number of jobs were not invoked
      assert JobTestHelper.performed_count == 5

      GenServer.stop worker
    end
  end

  describe "message ack" do
    setup do
      :meck.new TaskBunny.Consumer, [:passthrough]

      on_exit fn ->
        :meck.unload
      end
    end

    def get_ack_args do
      :meck.history(TaskBunny.Consumer)
      |> Enum.find_value(fn ({_pid, {_module, method, args}, _ret}) ->
        if method==:ack, do: args
      end)
    end

    test "acknowledges with true in succeeded when job is succeeded" do
      {:ok, worker} = Worker.start_link({TestJob, 1})
      payload = %{"hello" => "world"}

      SyncPublisher.push TestJob.queue_name, payload
      JobTestHelper.wait_for_perform()

      ack_args = get_ack_args()

      assert ack_args
      [_, _, succeeded] = ack_args
      assert succeeded

      GenServer.stop worker
    end

    test "acknowledges with false in succeeded when job is failed" do
      {:ok, worker} = Worker.start_link({TestJob, 1})
      payload = %{"fail" => true}

      SyncPublisher.push TestJob.queue_name, payload
      JobTestHelper.wait_for_perform()

      ack_args = get_ack_args()

      assert ack_args
      [_, _, succeeded] = ack_args
      refute succeeded

      GenServer.stop worker
    end
  end
end
