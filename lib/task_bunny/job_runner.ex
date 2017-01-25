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

  def invoke(job, payload, meta) do
    caller = self()

    spawn fn ->
      result = run_job_with_task(job, payload)
      send caller, {:job_finished, result, meta}
    end
  end

  defp run_job_with_task(job, payload) do
    # Spawn task supervisor
    {:ok, sv_pid} = Task.Supervisor.start_link()

    # Spawn task without link. It prevents parent process to crash when task is crashed.
    task = Task.Supervisor.async_nolink sv_pid, fn ->
      job.perform(payload)
    end

    # Yield the task
    ret_val =
      case Task.yield(task, job.timeout) do
        {:ok, result} ->
          # Job performed and returned the result
          result
        nil ->
          # Timeout
          Logger.error "TaskBunny.Worker - job timeout: #{inspect job} with #{inspect payload}"
          {:error, "#{inspect job} timed out with #{job.timeout}"}
        error ->
          # Crashed
          Logger.error "TaskBunny.Worker - job crashed: #{inspect job} with #{inspect payload}. Error: #{inspect error}"
          {:error, error}
      end

    # Kill task
    if Process.alive?(task.pid), do: Task.shutdown(task, 1000)

    # Kill task supervisor
    if Process.alive?(sv_pid), do: Process.exit(sv_pid, :normal)

    ret_val
  end
end
