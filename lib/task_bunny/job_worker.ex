defmodule TaskBunny.JobWorker do
  def start_link(job) do
    {:ok, spawn_link(fn -> init(job) end)}
  end

  def init(job) do
    run(job, job.queue_name)
  end

  def run(job, queue) do
    TaskBunny.BackgroundQueue.listen(queue,
      fn payload ->
        try do
          job.perform(payload)
        rescue
          e in RuntimeError -> {:error, e} 
        end
      end
    )
  end
end