defmodule TaskBunny.FailureBackendTest do
  use ExUnit.Case, async: false
  alias TaskBunny.{JobError, FailureBackend}
  import ExUnit.{CaptureLog, CaptureIO}

  defp setup_failure_backend_config(failure_backend) do
    :meck.new(Application, [:passthrough])

    :meck.expect(Application, :fetch_env, fn :task_bunny, :failure_backend ->
      {:ok, failure_backend}
    end)

    on_exit(fn -> :meck.unload() end)
  end

  defmodule TestBackend do
    use FailureBackend

    def report_job_error(error) do
      IO.puts("Hello #{error.job}")
    end
  end

  @job_error %JobError{
    job: TestJob,
    payload: %{"test" => 1},
    reject: false,
    failed_count: 1,
    queue: "test_queue",
    pid: self()
  }

  defp exception_error do
    Map.merge(@job_error, %{
      error_type: :exception,
      exception: RuntimeError.exception("Hello"),
      stacktrace: System.stacktrace()
    })
  end

  describe "report_job_error/1" do
    test "reports to Logger backend by default" do
      assert capture_log(fn ->
               FailureBackend.report_job_error(exception_error())
             end) =~ "TaskBunny - Elixir.TestJob failed for an exception"
    end

    test "reports to the custom backend" do
      setup_failure_backend_config([TestBackend])

      assert capture_io(fn ->
               FailureBackend.report_job_error(exception_error())
             end) =~ "Hello Elixir.TestJob"
    end
  end
end
