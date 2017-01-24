defmodule TaskBunny.WorkerSupervisor do
  use Supervisor
  alias TaskBunny.Experimental.Worker

  def start_link(jobs) do
    Supervisor.start_link(__MODULE__, jobs)
  end

  def init(jobs) do
    jobs
    |> Enum.map(fn ({job, concurrency}) ->
         worker(
          Worker,
          [%Worker{job: job, concurrency: concurrency}],
          id: "task_bunny.worker.#{job.queue_name}"
        )
       end)
    |> supervise(strategy: :one_for_one)
  end
end
