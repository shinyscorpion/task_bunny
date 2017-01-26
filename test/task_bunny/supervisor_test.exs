defmodule TaskBunny.SupervisorTest do
  use ExUnit.Case, async: false
  import TaskBunny.TestSupport.QueueHelper
  alias TaskBunny.TestSupport.JobTestHelper
  alias TaskBunny.TestSupport.JobTestHelper.TestJob
  alias TaskBunny.{Config, Connection, SyncPublisher}

  setup do
    clean(TestJob.all_queues())

    job = [
      job: TaskBunny.TestSupport.JobTestHelper.TestJob,
      concurrency: 1,
      host: :foo
    ]

    :meck.new Config, [:passthrough]
    :meck.expect Config, :hosts, fn -> [:foo] end
    :meck.expect Config, :connect_options, fn (:foo) -> "amqp://localhost" end
    :meck.expect Config, :jobs, fn -> [job] end

    JobTestHelper.setup

    {:ok, pid} = TaskBunny.Supervisor.start_link()

    on_exit fn ->
      :meck.unload
      if Process.alive?(pid), do: Supervisor.stop(pid)
    end

    :ok
  end

  test "starts connection and worker" do
    payload = %{"hello" => "world"}
    SyncPublisher.push :foo, TestJob, payload

    JobTestHelper.wait_for_perform
    assert List.first(JobTestHelper.performed_payloads) == payload
  end

  describe "AMQP connection is lost" do
    test "recovers by restarting connection and all workers" do
      conn_name = :"TaskBunny.Connection.foo"
      work_name = :"TaskBunny.Worker.Elixir.TaskBunny.TestSupport.JobTestHelper.TestJob"
      conn_pid = Process.whereis(conn_name)
      work_pid = Process.whereis(work_name)

      # Close the connection
      conn = Connection.get_connection(:foo)
      AMQP.Connection.close(conn)
      :timer.sleep(10)

      new_conn_pid = Process.whereis(conn_name)
      new_work_pid = Process.whereis(work_name)

      # Test if GenServer has different pids
      refute new_conn_pid == conn_pid
      refute new_work_pid == work_pid

      # Make sure worker handles the job
      payload = %{"hello" => "world"}
      SyncPublisher.push :foo, TestJob, payload

      JobTestHelper.wait_for_perform
      assert List.first(JobTestHelper.performed_payloads) == payload
    end
  end

  describe "a worker crashes" do
    test "restarts the worker but connection stays" do
      conn_name = :"TaskBunny.Connection.foo"
      work_name = :"TaskBunny.Worker.Elixir.TaskBunny.TestSupport.JobTestHelper.TestJob"
      conn_pid = Process.whereis(conn_name)
      work_pid = Process.whereis(work_name)

      # Kill worker
      Process.exit(work_pid, :kill)
      :timer.sleep(10)

      new_conn_pid = Process.whereis(conn_name)
      new_work_pid = Process.whereis(work_name)

      # Test if the worker is restarted and connection stays same.
      assert new_conn_pid == conn_pid
      refute new_work_pid == nil
      refute new_work_pid == work_pid
    end
  end
end
