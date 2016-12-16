defmodule TaskBunny.JobSupervisor do
  use Supervisor

  def start_link(jobs) do
    Supervisor.start_link(__MODULE__, jobs)
  end

  def init(jobs) do
    jobs
    |> Enum.map( fn job -> worker(IngameApi.JobWorker, [job]) end)
    |> supervise(strategy: :one_for_one)
  end
end