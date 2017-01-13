defmodule TaskBunny.JobWorkerSupervisorTest do
  use ExUnit.Case
  alias TaskBunny.{BackgroundQueue, JobWorkerSupervisor, JobWorker}
  alias TaskBunny.TestSupport.JobTestHelper
  alias TaskBunny.TestSupport.JobTestHelper.TestJob

  setup do
    BackgroundQueue.purge TestJob.queue_name

    JobTestHelper.setup

    on_exit fn ->
      BackgroundQueue.purge TestJob.queue_name
      JobTestHelper.teardown
    end

    :ok
  end

  test "starts job worker" do
    jobs = [{TestJob, 3}]

    {:ok, pid} = JobWorkerSupervisor.start_link(jobs)
    %{active: active} = Supervisor.count_children(pid)
    assert active == 1

    payload = %{"hello" => "world"}
    BackgroundQueue.push TestJob.queue_name, payload

    JobTestHelper.wait_for_perform
    assert List.first(JobTestHelper.performed_payloads) == payload

    Supervisor.stop(pid)
  end
end
