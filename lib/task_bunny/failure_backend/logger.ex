defmodule TaskBunny.FailureBackend.Logger do
  @moduledoc """
  Default failure backend that reports job errors to Logger.
  """
  use TaskBunny.FailureBackend
  require Logger
  alias TaskBunny.JobError

  # Callback for FailureBackend
  def report_job_error(error = %JobError{}) do
    get_job_error_message(error)
    |> do_report(error.reject)
  end

  @doc """
  Returns the message content for the job error.
  """
  @spec get_job_error_message(JobError.t) :: String.t
  def get_job_error_message(error = %JobError{error_type: :exception}) do
    """
    TaskBunny - #{error.job} failed for an exception.

    Exception:
    #{my_inspect error.exception}

    #{common_message error}

    Stacktrace:
    #{Exception.format_stacktrace(error.stacktrace)}
    """
  end

  def get_job_error_message(error = %JobError{error_type: :return_value}) do
    """
    TaskBunny - #{error.job} failed for an invalid return value.

    Return value:
    #{my_inspect error.return_value}

    #{common_message error}
    """
  end

  def get_job_error_message(error = %JobError{error_type: :exit}) do
    """
    TaskBunny - #{error.job} failed for EXIT signal.

    Reason:
    #{my_inspect error.reason}

    #{common_message error}
    """
  end

  def get_job_error_message(error = %JobError{error_type: :timeout}) do
    """
    TaskBunny - #{error.job} failed for timeout.

    #{common_message error}
    """
  end

  def get_job_error_message(error = %JobError{}) do
    """
    TaskBunny - Failed with the unknown error type.

    #{common_message error}
    """
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
