defmodule TaskBunny.FailureBackend.LoggerTest do
  use ExUnit.Case, async: false
  alias TaskBunny.JobError
  import TaskBunny.FailureBackend.Logger
  import ExUnit.CaptureLog

  @job_error %JobError{
    job: TestJob,
    payload: %{"test" => 1},
    reject: false,
    failed_count: 1,
    queue: "test_queue",
    pid: self()
  }

  @exception_error Map.merge(@job_error, %{
                     error_type: :exception,
                     exception: RuntimeError.exception("Hello"),
                     stacktrace: []
                   })

  @return_value_error Map.merge(@job_error, %{
                        error_type: :return_value,
                        return_value: {:error, :testing}
                      })

  @exit_error Map.merge(@job_error, %{
                error_type: :exit,
                reason: :just_testing
              })

  @timeout_error Map.merge(@job_error, %{
                   error_type: :timeout
                 })

  @unknown_error Map.merge(@job_error, %{
                   error_type: :invalid_type
                 })

  describe "report_job_error/1" do
    test "handles an exception" do
      assert capture_log(fn ->
               report_job_error(@exception_error)
             end) =~ "TaskBunny - Elixir.TestJob failed for an exception"
    end

    test "handles an invalid return value" do
      assert capture_log(fn ->
               report_job_error(@return_value_error)
             end) =~ "TaskBunny - Elixir.TestJob failed for an invalid return value"
    end

    test "handles the EXIT signal" do
      assert capture_log(fn ->
               report_job_error(@exit_error)
             end) =~ "TaskBunny - Elixir.TestJob failed for EXIT signal"
    end

    test "handles timeout" do
      assert capture_log(fn ->
               report_job_error(@timeout_error)
             end) =~ "TaskBunny - Elixir.TestJob failed for timeout"
    end

    test "handles unknown error type" do
      assert capture_log(fn ->
               report_job_error(@unknown_error)
             end) =~ "TaskBunny - Failed with the unknown error type"
    end
  end
end
