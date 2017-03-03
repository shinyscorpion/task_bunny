defmodule TaskBunny.Status.WorkerTest do
  use ExUnit.Case, async: false

  import TaskBunny.QueueTestHelper
  alias TaskBunny.{Config, Queue, JobTestHelper}
  alias JobTestHelper.TestJob

  @host :worker_test
  @supervisor :worker_test_supervisor
  @worker_supervisor :worker_test_worker_supervisor
  @queue1 "task_bunny.status.worker_test1"
  @queue2 "task_bunny.status.worker_test2"

  defmodule RejectJob do
    use TaskBunny.Job

    def perform(payload) do
      JobTestHelper.Tracer.performed payload

      :error
    end

    def retry_interval, do: 1
    def max_retry, do: 0
  end

  defp find_worker(workers, queue) do
    Enum.find(workers, fn %{queue: w_queue} -> queue == w_queue end)
  end

  defp all_queues do
    Queue.queue_with_subqueues(@queue1) ++
    Queue.queue_with_subqueues(@queue2)
  end

  defp mock_config do
    workers = [
      [host: @host, queue: @queue1, concurrency: 3],
      [host: @host, queue: @queue2, concurrency: 3]
    ]

    :meck.new Config, [:passthrough]
    :meck.expect Config, :hosts, fn -> [@host] end
    :meck.expect Config, :connect_options, fn (@host) -> "amqp://localhost" end
    :meck.expect Config, :workers, fn -> workers end
  end

  setup do
    clean(all_queues())

    mock_config()
    JobTestHelper.setup()

    TaskBunny.Supervisor.start_link(@supervisor, @worker_supervisor)
    JobTestHelper.wait_for_connection(@host)

    on_exit fn ->
      :meck.unload
      JobTestHelper.teardown
    end

    :ok
  end

  describe "runners" do
    test "running with no jobs being performed" do
      %{workers: workers} = TaskBunny.Status.overview(@supervisor)
      %{runners: runner_count} = List.first(workers)

      assert runner_count == 0
    end

    test "running with jobs being performed" do
      payload = %{"sleep" => 10_000}

      TestJob.enqueue(payload, host: @host, queue: @queue1)
      TestJob.enqueue(payload, host: @host, queue: @queue1)

      JobTestHelper.wait_for_perform(2)

      %{workers: workers} = TaskBunny.Status.overview(@supervisor)
      %{runners: runner_count} = find_worker(workers, @queue1)

      assert runner_count == 2
    end
  end

  describe "job stats" do
    test "jobs succeeded" do
      payload = %{"hello" => "world1"}

      TestJob.enqueue(payload, host: @host, queue: @queue1)
      JobTestHelper.wait_for_perform()

      %{workers: workers} = TaskBunny.Status.overview(@supervisor)
      %{stats: stats} = find_worker(workers, @queue1)

      assert stats.succeeded == 1
    end

    test "jobs failed" do
      payload = %{"fail" => "fail"}

      TestJob.enqueue(payload, host: @host, queue: @queue1)
      JobTestHelper.wait_for_perform()

      %{workers: workers} = TaskBunny.Status.overview(@supervisor)
      %{stats: stats} = find_worker(workers, @queue1)

      assert stats.failed == 1
    end

    test "jobs rejected" do
      payload = %{"fail" => "fail"}

      RejectJob.enqueue(payload, host: @host, queue: @queue2)
      JobTestHelper.wait_for_perform()

      %{workers: workers} = TaskBunny.Status.overview(@supervisor)
      %{stats: stats} = find_worker(workers, @queue2)

      assert stats.rejected == 1
    end
  end
end
