defmodule TaskBunny.JobWorkerTest do
  use ExUnit.Case
  alias TaskBunny.{Queue, JobWorker}
  alias TaskBunny.TestSupport.JobTestHelper
  alias TaskBunny.TestSupport.JobTestHelper.TestJob

  setup do
    Queue.purge TestJob.queue_name

    JobTestHelper.setup

    on_exit fn ->
      Queue.purge TestJob.queue_name
      JobTestHelper.teardown
    end

    :ok
  end

  describe "worker" do
    test "invokes a job with the payload" do
      {:ok, worker} = JobWorker.start_link({TestJob, 1})
      payload = %{"hello" => "world"}
      Queue.push TestJob.queue_name, payload

      JobTestHelper.wait_for_perform

      assert List.first(JobTestHelper.performed_payloads) == payload

      GenServer.stop worker
    end

    test "concurrency" do
      {:ok, worker} = JobWorker.start_link({TestJob, 5})
      payload = %{"sleep" => 10_000}

      # Run 10 jobs and each would take 10 seconds to finish
      Enum.each 1..10, fn (_) ->
        Queue.push TestJob.queue_name, payload
      end

      # This waits for up to 1 second
      assert JobTestHelper.wait_for_perform 5

      # Make sure more than specified number of jobs were not invoked
      assert JobTestHelper.performed_count == 5

      GenServer.stop worker
    end
  end

  describe "message ack" do
    setup do
      :meck.new Queue, [:passthrough]

      on_exit fn ->
        :meck.unload
      end
    end

    def get_ack_args do
      :meck.history(Queue)
      |> Enum.find_value(fn ({_pid, {_module, method, args}, _ret}) ->
        if method==:ack, do: args
      end)
    end

    test "acknowledges with true in succeeded when job is succeeded" do
      {:ok, worker} = JobWorker.start_link({TestJob, 1})
      payload = %{"hello" => "world"}

      Queue.push TestJob.queue_name, payload
      JobTestHelper.wait_for_perform
      :timer.sleep(10) # wait for message handled

      ack_args = get_ack_args

      assert ack_args
      [_, _, succeeded] = ack_args
      assert succeeded

      GenServer.stop worker
    end

    test "acknowledges with false in succeeded when job is failed" do
      {:ok, worker} = JobWorker.start_link({TestJob, 1})
      payload = %{"fail" => true}

      Queue.push TestJob.queue_name, payload
      JobTestHelper.wait_for_perform
      :timer.sleep(10) # wait for message handled

      ack_args = get_ack_args

      assert ack_args
      [_, _, succeeded] = ack_args
      refute succeeded

      GenServer.stop worker
    end
  end
end
