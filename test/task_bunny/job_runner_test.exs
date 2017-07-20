defmodule TaskBunny.JobRunnerTest do
  use ExUnit.Case
  alias TaskBunny.JobRunner

  defmodule SampleJobs do
    defmodule CrashJob do
      use TaskBunny.Job

      def perform(_payload) do
        raise "Oops"
      end
    end

    defmodule TimeoutJob do
      use TaskBunny.Job

      def timeout, do: 10

      def perform(_payload) do
        :timer.sleep(10_000)
        :ok
      end
    end

    defmodule NormalJob do
      use TaskBunny.Job

      def perform(_payload) do
        :ok
      end
    end

    defmodule ErrorJob do
      use TaskBunny.Job

      def perform(_payload) do
        {:error, "failed!"}
      end
    end

    defmodule PayloadJob do
      use TaskBunny.Job

      def perform(payload) do
        {:ok, payload}
      end
    end
  end

  describe "invoke" do
    defp message(job, payload, meta) do
      body = TaskBunny.Message.encode!(job, payload)
      {body, meta}
    end

    test "runs the job and notifies when it has finished" do
      payload = %{hello: "world"}
      message = message(SampleJobs.NormalJob, payload, %{a: "b"})
      JobRunner.invoke(SampleJobs.NormalJob, payload, message)

      assert_receive {:job_finished, :ok, ^message}
    end

    test "invokes perform method with the given payload" do
      payload = %{hello: "world"}
      JobRunner.invoke(SampleJobs.PayloadJob, payload, nil)

      assert_receive {:job_finished, {:ok, ^payload}, nil}
    end

    test "handles job error" do
      JobRunner.invoke(SampleJobs.ErrorJob, nil, nil)

      assert_receive {:job_finished, {:error, %{return_value: {:error, "failed!"}}}, nil}
    end

    test "handles job crashing" do
      JobRunner.invoke(SampleJobs.CrashJob, nil, nil)

      assert_receive {:job_finished, {:error, _}, nil}
    end

    test "handles timed-out job" do
      JobRunner.invoke(SampleJobs.TimeoutJob, nil, nil)

      assert_receive {:job_finished, {:error, _}, nil}, 1000
    end
  end
end
