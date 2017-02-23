defmodule TaskBunny.SupervisorTest do
  use ExUnit.Case, async: false
  import TaskBunny.TestSupport.QueueHelper
  alias TaskBunny.TestSupport.JobTestHelper
  alias TaskBunny.TestSupport.JobTestHelper.TestJob
  alias TaskBunny.{Config, Connection}

  @host :sv_test

  setup do
    clean(TestJob.all_queues())

    job = [
      job: TaskBunny.TestSupport.JobTestHelper.TestJob,
      concurrency: 1,
      host: @host
    ]

    :meck.new Config, [:passthrough]
    :meck.expect Config, :hosts, fn -> [@host] end
    :meck.expect Config, :connect_options, fn (@host) -> "amqp://localhost" end
    :meck.expect Config, :jobs, fn -> [job] end

    JobTestHelper.setup

    {:ok, pid} = TaskBunny.Supervisor.start_link(:supevisor_test)
    :timer.sleep(50)

    on_exit fn ->
      :meck.unload
      if Process.alive?(pid), do: Supervisor.stop(pid)
    end

    :ok
  end

  test "starts connection and worker" do
    payload = %{"hello" => "world"}
    TestJob.enqueue(payload, host: @host)

    JobTestHelper.wait_for_perform
    assert List.first(JobTestHelper.performed_payloads) == payload
  end

  describe "AMQP connection is lost" do
    test "recovers by restarting connection and all workers" do
      conn_name = :"TaskBunny.Connection.#{@host}"
      work_name = :"TaskBunny.Worker.Elixir.TaskBunny.TestSupport.JobTestHelper.TestJob"
      conn_pid = Process.whereis(conn_name)
      work_pid = Process.whereis(work_name)

      # Close the connection
      conn = Connection.get_connection(@host)
      AMQP.Connection.close(conn)
      :timer.sleep(50)

      new_conn_pid = Process.whereis(conn_name)
      new_work_pid = Process.whereis(work_name)

      # Test if GenServer has different pids
      refute new_conn_pid == conn_pid
      refute new_work_pid == work_pid

      # Make sure worker handles the job
      payload = %{"hello" => "world"}
      TestJob.enqueue(payload, host: @host)

      JobTestHelper.wait_for_perform()
      assert List.first(JobTestHelper.performed_payloads) == payload
    end
  end

  describe "a worker crashes" do
    test "restarts the worker but connection stays" do
      conn_name = :"TaskBunny.Connection.#{@host}"
      work_name = :"TaskBunny.Worker.Elixir.TaskBunny.TestSupport.JobTestHelper.TestJob"
      conn_pid = Process.whereis(conn_name)
      work_pid = Process.whereis(work_name)

      # Kill worker
      Process.exit(work_pid, :kill)
      :timer.sleep(50)

      new_conn_pid = Process.whereis(conn_name)
      new_work_pid = Process.whereis(work_name)

      # Test if the worker is restarted and connection stays same.
      assert new_conn_pid == conn_pid
      refute new_work_pid == nil
      refute new_work_pid == work_pid
    end
  end
end
