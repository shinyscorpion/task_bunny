defmodule TaskBunny.FailureBackend do
  @moduledoc """
  A behaviour module to implement the your own failure backend.

  Note the backend is called only for the errors caught during job processing.
  Any other errors won't be reported to the backend.

  ## Configuration

  By default, TaskBunny reports the job failures to Logger.
  If you want to report the error to different services, you can configure
  your custom failure backend.

      config :task_bunny, failure_backend: [YourApp.CustomFailureBackend]

  You can also report the errors to the multiple backends. For example, if you
  want to use our default Logger backend with your custom backend you can
  configure like below:

      config :task_bunny, failure_backend: [
        TaskBunny.FailureBackend.Logger,
        YourApp.CustomFailureBackend
      ]

  ## Example

  See the implmentation of `TaskBunny.FailureBackend.Logger`.

  ## Argument

  See `TaskBunny.JobError` for the details.

  """
  alias TaskBunny.{JobError, Config, FailureBackend}

  @doc """
  Callback to report a job error.
  """
  @callback report_job_error(JobError.t()) :: any

  defmacro __using__(_options \\ []) do
    quote do
      @behaviour FailureBackend
    end
  end

  @doc false
  @spec report_job_error(JobError.t()) :: :ok
  def report_job_error(job_error = %JobError{}) do
    Config.failure_backend()
    |> Enum.each(& &1.report_job_error(job_error))
  end
end
