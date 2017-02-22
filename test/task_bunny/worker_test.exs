defmodule TaskBunny.WorkerTest do
  use ExUnit.Case, async: false
  import TaskBunny.TestSupport.QueueHelper
  alias TaskBunny.{Connection, Worker, Queue}
  alias TaskBunny.TestSupport.{
    JobTestHelper,
    JobTestHelper.TestJob
  }

  setup do
    clean(TestJob.all_queues())

    JobTestHelper.setup

    on_exit fn ->
      JobTestHelper.teardown
    end

    :ok
  end

  describe "worker" do
    test "invokes a job with the payload" do
      {:ok, worker} = Worker.start_link({TestJob, 1})
      payload = %{"hello" => "world1"}

      TestJob.enqueue(payload)
      JobTestHelper.wait_for_perform()

      assert List.first(JobTestHelper.performed_payloads) == payload

      GenServer.stop worker
    end

    test "consumes the message" do
      {:ok, worker} = Worker.start_link({TestJob, 1})
      [main, retry, rejected] = TestJob.all_queues()
      payload = %{"hello" => "world1"}

      TestJob.enqueue(payload)
      JobTestHelper.wait_for_perform()

      conn = Connection.get_connection()
      %{message_count: main_count} = Queue.state(conn, main)
      %{message_count: retry_count} = Queue.state(conn, retry)
      %{message_count: rejected_count} = Queue.state(conn, rejected)

      assert main_count == 0
      assert retry_count == 0
      assert rejected_count == 0

      GenServer.stop worker
    end

    test "concurrency" do
      {:ok, worker} = Worker.start_link({TestJob, 5})
      payload = %{"sleep" => 10_000}

      # Run 10 jobs and each would take 10 seconds to finish
      Enum.each 1..10, fn (_) ->
        TestJob.enqueue(payload)
      end

      # This waits for up to 1 second
      assert JobTestHelper.wait_for_perform 5

      # Make sure more than specified number of jobs were not invoked
      assert JobTestHelper.performed_count == 5

      GenServer.stop worker
    end
  end

  describe "retry" do
    test "sends failed job to retry queue" do
      {:ok, worker} = Worker.start_link({TestJob, 1})
      [main, retry, rejected] = TestJob.all_queues()
      payload = %{"fail" => true}

      TestJob.enqueue(payload)
      JobTestHelper.wait_for_perform()

      conn = Connection.get_connection()
      %{message_count: main_count} = Queue.state(conn, main)
      %{message_count: retry_count} = Queue.state(conn, retry)
      %{message_count: rejected_count} = Queue.state(conn, rejected)

      assert main_count == 0
      assert retry_count == 1
      assert rejected_count == 0

      GenServer.stop(worker)
    end

    def reset_test_job_retry_interval(interval) do
      :meck.new(JobTestHelper.RetryInterval, [:passthrough])
      :meck.expect(JobTestHelper.RetryInterval, :interval, fn () -> interval end)
      TestJob.declare_queue(Connection.get_connection())
    end

    test "retries max_retry times then sends to rejected queue" do
      # Sets up TestJob to retry shortly
      reset_test_job_retry_interval(5)

      {:ok, worker} = Worker.start_link({TestJob, 1})
      [main, retry, rejected] = TestJob.all_queues()
      payload = %{"fail" => true}

      TestJob.enqueue(payload)
      JobTestHelper.wait_for_perform(11)

      # 1 normal + 10 retries = 11
      assert JobTestHelper.performed_count == 11

      conn = Connection.get_connection()
      %{message_count: main_count} = Queue.state(conn, main)
      %{message_count: retry_count} = Queue.state(conn, retry)
      %{message_count: rejected_count} = Queue.state(conn, rejected)

      assert main_count == 0
      assert retry_count == 0
      assert rejected_count == 1

      GenServer.stop worker
    end
  end

  test "invalid payload" do
    :meck.expect TaskBunny.Consumer, :ack, fn (_, _, _) -> nil end

    assert Worker.handle_info({:basic_deliver, "}", %{}}, %{
      job: TestJob,
      runners: 0,
      host: :default,
      channel: nil,
      job_stats: %{
        failed: 0,
        succeeded: 0,
        rejected: 0,
      },
    }) == {:noreply,
      %{
        channel: nil,
        host: :default,
        job: TestJob,
        runners: 0,
        job_stats: %{failed: 0, rejected: 1, succeeded: 0},
      }
    }
  end
end
