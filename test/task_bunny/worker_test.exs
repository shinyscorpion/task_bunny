defmodule TaskBunny.WorkerTest do
  use ExUnit.Case, async: false
  import TaskBunny.QueueTestHelper
  alias TaskBunny.{Connection, Worker, Queue, JobTestHelper}
  alias JobTestHelper.TestJob

  @queue "task_bunny.worker_test"

  defp all_queues do
    Queue.queue_with_subqueues(@queue)
  end

  defp start_worker(concurrency \\ 1) do
    {:ok, worker} = Worker.start_link(queue: @queue, concurrency: concurrency)
    worker
  end

  setup do
    clean(all_queues())
    JobTestHelper.setup

    on_exit fn ->
      JobTestHelper.teardown
    end

    :ok
  end

  describe "worker" do
    test "invokes a job with the payload" do
      worker = start_worker()
      payload = %{"hello" => "world1"}

      TestJob.enqueue(payload, queue: @queue)
      JobTestHelper.wait_for_perform()

      assert List.first(JobTestHelper.performed_payloads) == payload

      GenServer.stop worker
    end

    test "consumes the message" do
      worker = start_worker()
      [main, retry, rejected, _scheduled] = all_queues()
      payload = %{"hello" => "world1"}

      TestJob.enqueue(payload, queue: @queue)
      JobTestHelper.wait_for_perform()

      conn = Connection.get_connection!()
      %{message_count: main_count} = Queue.state(conn, main)
      %{message_count: retry_count} = Queue.state(conn, retry)
      %{message_count: rejected_count} = Queue.state(conn, rejected)

      assert main_count == 0
      assert retry_count == 0
      assert rejected_count == 0

      GenServer.stop worker
    end

    test "concurrency" do
      worker = start_worker(5)
      payload = %{"sleep" => 10_000}

      # Run 10 jobs and each would take 10 seconds to finish
      Enum.each 1..10, fn (_) ->
        TestJob.enqueue(payload, queue: @queue)
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
      worker = start_worker()
      [main, retry, rejected, _scheduled] = all_queues()
      payload = %{"fail" => true}

      TestJob.enqueue(payload, queue: @queue)
      JobTestHelper.wait_for_perform()

      conn = Connection.get_connection!()
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
    end

    test "retries max_retry times then sends to rejected queue" do
      # Sets up TestJob to retry shortly
      reset_test_job_retry_interval(5)

      worker = start_worker()
      [main, retry, rejected, _scheduled] = all_queues()
      payload = %{"fail" => true}

      TestJob.enqueue(payload, queue: @queue)
      JobTestHelper.wait_for_perform(11)

      # 1 normal + 10 retries = 11
      assert JobTestHelper.performed_count == 11

      conn = Connection.get_connection!()
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
      host: :default,
      queue: @queue,
      concurrency: 1,
      channel: nil,
      runners: 0,
      job_stats: %{
        failed: 0,
        succeeded: 0,
        rejected: 0,
      },
    }) == {:noreply,
      %{
        host: :default,
        queue: @queue,
        concurrency: 1,
        channel: nil,
        runners: 0,
        job_stats: %{failed: 0, rejected: 1, succeeded: 0},
      }
    }
  end
end
