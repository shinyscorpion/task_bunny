defmodule TaskBunny.JobRunner do
  @moduledoc """
  JobRunner wraps up job execution and provides you abilities:

  - invoking jobs concurrently (unblocking job execution)
  - handling a job crashing
  - handling timeout

  ## Signal

  Once the job has finished it sends a message with a tuple consisted with:

  - atom indicating message type: :job_finished
  - result: :ok or {:error, details}
  - meta: meta data for the job

  After sending the messsage, JobRunner shuts down all processes it started.
  """

  require Logger

  @doc ~S"""
  Invokes the given job with the given payload.

  The job is run in a seperate process, which is killed after the job.timeout if the job has not finished yet.
  A :error message is send to the :job_finished of the caller if the job times out.
  """
  @spec invoke(atom, any, any) :: {:ok | :error, any}
  def invoke(job, payload, meta) do
    caller = self()

    timer = Process.send_after caller, {:job_finished, {:error, "#{inspect job} timed out with #{job.timeout}"}, payload, meta}, job.timeout

    pid = spawn fn ->
      send caller, {:job_finished, run_job(job, payload), payload, meta}
      Process.cancel_timer timer
    end

    :timer.kill_after(job.timeout + 10, pid)
  end

  # Performs a job with the given payload.
  # Any raises or throws in the perform are caught and turned into an :error tuple.
  @spec run_job(atom, any) :: :ok | {:ok, any} | {:error, any}
  defp run_job(job, payload) do
    job.perform(payload)
  rescue
    error ->
      Logger.error "TaskBunny.Worker - Runner rescued #{inspect error}"
      {:error, error}
  catch
    _, reason ->
      Logger.error "TaskBunny.Worker - Runner caught reason: #{inspect reason}"
      {:error, reason}
  end
end
