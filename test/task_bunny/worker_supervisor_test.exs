defmodule TaskBunny.WorkerSupervisorTest do
  use ExUnit.Case, async: false
  import TaskBunny.TestSupport.QueueHelper
  alias TaskBunny.{Connection, Queue, WorkerSupervisor}
  alias TaskBunny.TestSupport.JobTestHelper
  alias TaskBunny.TestSupport.JobTestHelper.TestJob

  @test_job_worker :"TaskBunny.Worker.Elixir.TaskBunny.TestSupport.JobTestHelper.TestJob"

  setup do
    clean(TestJob.all_queues())
    JobTestHelper.setup

    on_exit fn ->
      JobTestHelper.teardown
    end

    :ok
  end

  defp start_worker_supervisor do
    jobs = [{:default, TestJob, 3}]
    {:ok, pid} = WorkerSupervisor.start_link(jobs, :woker_supervisor_test)
    pid
  end

  defp wait_for_worker_up(name \\ @test_job_worker) do
    Enum.find_value 1..100, fn (_) ->
      if pid = Process.whereis(name) do
        %{consuming: consuming} = GenServer.call(pid, :status)
        !is_nil(consuming)
        :timer.sleep(10)
        true
      else
        :timer.sleep(10)
        false
      end
    end
  end

  test "starts job worker" do
    pid = start_worker_supervisor()
    %{active: active} = Supervisor.count_children(pid)
    assert active == 1

    payload = %{"hello" => "world"}
    TestJob.enqueue(payload)

    JobTestHelper.wait_for_perform()
    assert List.first(JobTestHelper.performed_payloads) == payload

    Supervisor.stop(pid)
  end

  describe "graceful_halt" do
    test "stops workers to consuming the job" do
      pid = start_worker_supervisor()
      wait_for_worker_up()

      assert WorkerSupervisor.graceful_halt(pid, 1000) == :ok

      payload = %{"hello" => "world2"}
      TestJob.enqueue(payload)
      :timer.sleep(50)

      assert JobTestHelper.performed_count() == 0

      %{message_count: count} = Queue.state(
        Connection.get_connection(), TestJob.queue_name()
      )

      assert count == 1
    end

    test "doesn't stop workers if the current running job didn't finish before timeout" do
      pid = start_worker_supervisor()
      wait_for_worker_up()

      payload = %{"sleep" => 60_000}
      TestJob.enqueue(payload)
      JobTestHelper.wait_for_perform()

      assert {:error, _} = WorkerSupervisor.graceful_halt(pid, 100)
    end

    test "waits for current runnning jobs to be finished" do
      pid = start_worker_supervisor()
      wait_for_worker_up()

      payload = %{"sleep" => 200}
      TestJob.enqueue(payload)
      JobTestHelper.wait_for_perform()

      assert :ok = WorkerSupervisor.graceful_halt(pid, 1000)
    end
  end
end
