defmodule TaskBunny.ErrorReporter do
  @moduledoc """
  A behaviour module to implment the your own error reporting backend.
  """
  alias TaskBunny.JobError

  @doc false
  @spec report_job_error(JobError.t) :: :ok
  def report_job_error(job_error) do

    :ok
  end
end
