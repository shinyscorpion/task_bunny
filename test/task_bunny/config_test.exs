defmodule TaskBunny.ConfigTest do
  use ExUnit.Case, async: false
  alias TaskBunny.Config

  describe "jobs" do
    defmodule SampleJobs do
      defmodule HelloJob do
        use TaskBunny.Job
        def perform(_payload), do: nil
      end
      defmodule HolaJob do
        use TaskBunny.Job
        def perform(_payload), do: nil
      end
      defmodule CiaoJob do
        use TaskBunny.Job
        def perform(_payload), do: nil
      end
    end

    setup do
      envs = [
        jobs: [
          [job: SampleJobs.HelloJob, concurrency: 5],
          [job: SampleJobs.HolaJob, concurrency: 2]
        ],
        extra_jobs: [
          [job: SampleJobs.CiaoJob, concurrency: 3]
        ],
        included_applications: [],
        hosts: [default: [connect_options: "amqp://localhost"]]
      ]

      :meck.new Application, [:passthrough]
      :meck.expect Application, :get_all_env, fn (:task_bunny) -> envs end

      on_exit(fn -> :meck.unload end)

      :ok
    end

    test "merges all jobs" do
      all_jobs = [
        [job: SampleJobs.HelloJob, concurrency: 5],
        [job: SampleJobs.HolaJob, concurrency: 2],
        [job: SampleJobs.CiaoJob, concurrency: 3]
      ]
      assert Config.jobs == all_jobs
    end
  end
end
