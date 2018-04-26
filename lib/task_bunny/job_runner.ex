defmodule TaskBunny.JobRunner do
  # Handles job invocation concerns.
  #
  # This module is private to TaskBunny and should not be accessed directly.
  #
  # JobRunner wraps up job execution and provides you abilities:
  #
  # - invoking jobs concurrently (unblocking job execution)
  # - handling a job crashing
  # - handling timeout
  #
  # ## Signal
  #
  # Once the job has finished it sends a message with a tuple consisted with:
  #
  # - atom indicating message type: :job_finished
  # - result: :ok or {:error, details}
  # - meta: meta data for the job
  #
  # After sending the messsage, JobRunner shuts down all processes it started.
  #
  @moduledoc false

  require Logger
  alias TaskBunny.JobError

  @doc ~S"""
  Invokes the given job with the given payload.

  The job run in a seperate process. If the job.timeout is equals to :infinity 
  then the process will run with no concerns about timeouts. 
  Otherwise it will be killed after the job.timeout if the job has not finished yet.
  A :error message is send to the :job_finished of the caller if the job times out.
  """
  @spec invoke(atom, any, {any, any}) :: {:ok | :error, any}
  def invoke(job, payload, message) do
    caller = self()

    case job.timeout do
      :infinity ->
        spawn(fn ->
          send(caller, {:job_finished, run_job(job, payload), message})
        end)

      timeout ->
        timeout_error = {:error, JobError.handle_timeout(job, payload)}

        timer =
          Process.send_after(
            caller,
            {:job_finished, timeout_error, message},
            timeout
          )

        pid =
          spawn(fn ->
            send(caller, {:job_finished, run_job(job, payload), message})
            Process.cancel_timer(timer)
          end)

        :timer.kill_after(job.timeout + 10, pid)
    end
  end

  # Performs a job with the given payload.
  # Any raises or throws in the perform are caught and turned into an :error tuple.
  @spec run_job(atom, any) :: :ok | {:ok, any} | {:error, any}
  defp run_job(job, payload) do
    case job.perform(payload) do
      :ok -> :ok
      {:ok, something} -> {:ok, something}
      error -> {:error, JobError.handle_return_value(job, payload, error)}
    end
  rescue
    error ->
      Logger.debug("TaskBunny.JobRunner - Runner rescued #{inspect(error)}")
      {:error, JobError.handle_exception(job, payload, error)}
  catch
    _, reason ->
      Logger.debug("TaskBunny.JobRunner - Runner caught reason: #{inspect(reason)}")
      {:error, JobError.handle_exit(job, payload, reason)}
  end
end
