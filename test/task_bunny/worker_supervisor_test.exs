defmodule TaskBunny.WorkerSupervisorTest do
  use ExUnit.Case

  import TaskBunny.TestSupport.QueueHelper
  alias TaskBunny.{Connection, SyncPublisher, WorkerSupervisor}
  alias TaskBunny.TestSupport.JobTestHelper
  alias TaskBunny.TestSupport.JobTestHelper.TestJob

  setup do
    clean(TestJob.all_queues())
    JobTestHelper.setup
    TestJob.declare_queue(Connection.get_connection())

    on_exit fn ->
      JobTestHelper.teardown
    end

    :ok
  end

  test "starts job worker" do
    jobs = [{:default, TestJob, 3}]

    {:ok, pid} = WorkerSupervisor.start_link(jobs)
    %{active: active} = Supervisor.count_children(pid)
    assert active == 1

    payload = %{"hello" => "world"}
    SyncPublisher.push TestJob.queue_name, payload

    JobTestHelper.wait_for_perform
    assert List.first(JobTestHelper.performed_payloads) == payload

    Supervisor.stop(pid)
  end
end
