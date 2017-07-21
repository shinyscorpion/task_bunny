defmodule TaskBunny.FailureBackend.Logger do
  @moduledoc """
  Default failure backend that reports job errors to Logger.
  """
  use TaskBunny.FailureBackend
  require Logger
  alias TaskBunny.JobError

  def report_job_error(error = %JobError{error_type: :exception}) do
    message = """
    TaskBunny - #{error.job} failed for an exception.

    Exception:
    #{my_inspect error.exception}

    #{common_message error}

    Stacktrace:
    #{Exception.format_stacktrace(error.stacktrace)}
    """

    do_report(message, error.reject)
  end

  def report_job_error(error = %JobError{error_type: :return_value}) do
    message = """
    TaskBunny - #{error.job} failed for an invalid return value.

    Return value:
    #{my_inspect error.return_value}

    #{common_message error}
    """

    do_report(message, error.reject)
  end

  def report_job_error(error = %JobError{error_type: :exit}) do
    message = """
    TaskBunny - #{error.job} failed for EXIT signal.

    Reason:
    #{my_inspect error.reason}

    #{common_message error}
    """

    do_report(message, error.reject)
  end

  def report_job_error(error = %JobError{error_type: :timeout}) do
    message = """
    TaskBunny - #{error.job} failed for timeout.

    #{common_message error}
    """

    do_report(message, error.reject)
  end

  def report_job_error(error) do
    message = """
    TaskBunny - Failed with the unknown error type.

    Error dump:
    #{my_inspect error}
    """

    do_report(message, true)
  end

  defp do_report(message, rejected) do
    if rejected do
      Logger.error message
    else
      Logger.warn message
    end
  end

  defp common_message(error) do
    """
    Payload:
      #{my_inspect error.payload}

    History:
      - Failed count: #{error.failed_count}
      - Reject: #{error.reject}

    Worker:
      - Queue: #{error.queue}
      - Concurrency: #{error.concurrency}
      - PID: #{inspect error.pid}
    """
  end

  defp my_inspect(arg) do
    inspect arg, pretty: true, width: 100
  end
end
