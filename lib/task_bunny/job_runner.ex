defmodule TaskBunny.JobRunner do
  def execute do
    receive do
      {sender, job, payload, meta} ->
        result = execute_job(job, payload, meta)
        send sender, {:finish_job, result, meta}
    end
  end

  def execute_job(job, payload, meta) do
    try
      job.perform(payload, meta)
    rescue
      e in RuntimeError -> {:error, e}
    end
  end
end
