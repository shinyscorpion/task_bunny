defmodule TaskBunny.Status.WorkerTest do
  use ExUnit.Case, async: false

  import TaskBunny.TestSupport.QueueHelper
  alias TaskBunny.Config
  alias TaskBunny.TestSupport.JobTestHelper
  alias TaskBunny.TestSupport.JobTestHelper.TestJob

  @host :worker_test
  @supervisor :worker_test_supervisor

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

  defp setup_config do
    jobs = [
      [
        job: TestJob,
        concurrency: 3,
        host: @host,
      ],
      [
        job: RejectJob,
        concurrency: 3,
        host: @host,
      ],
    ]

    :meck.new Config, [:passthrough]
    :meck.expect Config, :hosts, fn -> [@host] end
    :meck.expect Config, :connect_options, fn (@host) -> "amqp://localhost" end
    :meck.expect Config, :jobs, fn -> jobs end
  end

  setup do
    clean(TestJob.all_queues())

    setup_config()
    JobTestHelper.setup()

    TaskBunny.Supervisor.start_link(:worker_test_supervisor)
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

      TestJob.enqueue(payload, host: @host)
      TestJob.enqueue(payload, host: @host)

      JobTestHelper.wait_for_perform(2)

      %{workers: workers} = TaskBunny.Status.overview(@supervisor)
      %{runners: runner_count} = find_worker(workers, TestJob)

      assert runner_count == 2
    end
  end

  describe "job stats" do
    test "jobs succeeded" do
      payload = %{"hello" => "world1"}

      TestJob.enqueue(payload)
      JobTestHelper.wait_for_perform()

      %{workers: workers} = TaskBunny.Status.overview(@supervisor)
      %{stats: stats} = find_worker(workers, TestJob)

      assert stats.succeeded == 1
    end

    test "jobs failed" do
      payload = %{"fail" => "fail"}

      TestJob.enqueue(payload)
      JobTestHelper.wait_for_perform()

      %{workers: workers} = TaskBunny.Status.overview(@supervisor)
      %{stats: stats} = find_worker(workers, TestJob)

      assert stats.failed == 1
    end

    test "jobs rejected" do
      payload = %{"fail" => "fail"}

      RejectJob.enqueue(payload)
      JobTestHelper.wait_for_perform()

      %{workers: workers} = TaskBunny.Status.overview(@supervisor)
      %{stats: stats} = find_worker(workers, RejectJob)

      assert stats.rejected == 1
    end
  end
end
