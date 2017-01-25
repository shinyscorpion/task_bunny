defmodule TaskBunny.Status.WorkerTest do
  use ExUnit.Case, async: false

  import TaskBunny.TestSupport.QueueHelper
  alias TaskBunny.{SyncPublisher, Config}
  alias TaskBunny.TestSupport.JobTestHelper
  alias TaskBunny.TestSupport.JobTestHelper.TestJob

  defmodule RejectJob do
    use TaskBunny.Job

    def perform(payload) do
      JobTestHelper.Tracer.performed payload

      :error
    end

    def retry_interval, do: 1
    def max_retry, do: 0
  end

  defp find_worker(workers, job_search) do
    Enum.find(workers, fn %{job: job} -> job == job_search end)
  end

  setup do
    clean(TestJob.all_queues())

    jobs = [
      [
        job: TaskBunny.TestSupport.JobTestHelper.TestJob,
        concurrency: 3,
        host: :foo,
      ],
      [
        job: TaskBunny.Status.WorkerTest.RejectJob,
        concurrency: 3,
        host: :foo,
      ],
    ]

    :meck.new Config, [:passthrough]
    :meck.expect Config, :hosts, fn -> [:foo] end
    :meck.expect Config, :connect_options, fn (:foo) -> "amqp://localhost" end
    :meck.expect Config, :jobs, fn -> jobs end

    JobTestHelper.setup

    {:ok, pid} = TaskBunny.Supervisor.start_link(:foo_supervisor)

    on_exit fn ->
      :meck.unload

      JobTestHelper.teardown

      if Process.alive?(pid), do: Supervisor.stop(pid)
    end

    :ok
  end

  describe "runners" do
    test "running with no jobs being performed" do
      %{workers: workers} = TaskBunny.Status.overview(:foo_supervisor)

      %{runners: runner_count} = List.first(workers)

      assert runner_count == 0
    end

    test "running with jobs being performed" do
      payload = %{"sleep" => 10_000}

      Process.sleep(10)

      SyncPublisher.push :foo, TestJob.queue_name, payload
      SyncPublisher.push :foo, TestJob.queue_name, payload

      JobTestHelper.wait_for_perform(2)

      %{workers: workers} = TaskBunny.Status.overview(:foo_supervisor)

      %{runners: runner_count} = find_worker(workers, TaskBunny.TestSupport.JobTestHelper.TestJob)

      assert runner_count == 2
    end
  end

  describe "job stats" do
    test "jobs succeeded" do
      payload = %{"hello" => "world1"}

      SyncPublisher.push TestJob, payload

      JobTestHelper.wait_for_perform()

      %{workers: workers} = TaskBunny.Status.overview(:foo_supervisor)

      %{stats: stats} = find_worker(workers, TaskBunny.TestSupport.JobTestHelper.TestJob)

      assert stats.succeeded == 1
    end

    test "jobs failed" do
      payload = %{"fail" => "fail"}

      SyncPublisher.push TestJob, payload

      JobTestHelper.wait_for_perform()

      %{workers: workers} = TaskBunny.Status.overview(:foo_supervisor)

      %{stats: stats} = find_worker(workers, TaskBunny.TestSupport.JobTestHelper.TestJob)

      assert stats.failed == 1
    end

    test "jobs rejected" do
      payload = %{"fail" => "fail"}

      SyncPublisher.push TaskBunny.Status.WorkerTest.RejectJob, payload

      JobTestHelper.wait_for_perform()

      %{workers: workers} = TaskBunny.Status.overview(:foo_supervisor)

      %{stats: stats} = find_worker(workers, TaskBunny.Status.WorkerTest.RejectJob)

      assert stats.rejected == 1
    end
  end
end