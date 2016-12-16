defmodule TaskBunny.JobWorkerTest do
  use ExUnit.Case

  import TaskBunny.QueueHelper

  alias TaskBunny.{BackgroundQueue, Job, JobWorker}

  defmodule ExitJob do
    use Job, id: "exit_job"

    def perform(_) do
      exit(:normal)
    end
  end

  describe "job worker" do
    test "waits for and performs correct job" do
      queue = "jobs.exit_job"

      TaskBunny.QueueHelper.clean([queue])

      BackgroundQueue.push queue, "Do this"
    
      {exit_code, _} =  try do
        task = Task.async(fn -> JobWorker.init(ExitJob) end)

        Task.await task, 1000
      catch
        :exit, reason -> reason
      end

      assert exit_code == :normal
    end

    test "waits for and does not perform other jobs" do
      queue = "jobs.other_job"
      
      TaskBunny.QueueHelper.clean([queue])

      BackgroundQueue.push queue, "Do this"
    
      {exit_code, _} =  try do
        task = Task.async(fn -> JobWorker.init(ExitJob) end)

        Task.await task, 1000
      catch
        :exit, reason -> reason
      end

      assert exit_code == :timeout
    end
  end
end