defmodule TaskBunny.ConfigTest do
  use ExUnit.Case, async: false
  alias TaskBunny.Config

  defp test_config do
    [
      queue: [
        namespace: "test.",
        queues: [
          [name: "high", worker: [concurrency: 10], jobs: ["High.*"]],
          [name: "normal", jobs: :default],
          [name: "low", worker: false, jobs: [SlowJob]]
        ]
      ],
      extra_queue: [
        namespace: "extra.",
        queues: [
          [name: "queue1", worker: [concurrency: 1], jobs: ["Extra.*"], host: :extra]
        ]
      ]
    ]
  end

  setup do
    :meck.new Application, [:passthrough]
    :meck.expect Application, :get_all_env, fn (:task_bunny) -> test_config() end

    on_exit(fn -> :meck.unload end)

    :ok
  end

  describe "queues" do
    test "combines all queue configs and sets namespace" do
      queue_names = Config.queues
                    |> Enum.map(fn (queue) -> queue[:name] end)

      assert queue_names == ["test.high", "test.normal", "test.low", "extra.queue1"]
    end
  end

  describe "workers" do
    test "lists up information for workers" do
      assert Config.workers == [
        [queue: "test.high", concurrency: 10, host: :default],
        [queue: "test.normal", concurrency: 2, host: :default],
        [queue: "extra.queue1", concurrency: 1, host: :extra]
      ]
    end
  end

  describe "queue_for_job" do
    test "returns matched queue" do
      assert Config.queue_for_job(High.TestJob) == "test.high"
      assert Config.queue_for_job(SlowJob) == "test.low"
      assert Config.queue_for_job(SampleJob) == "test.normal"
      assert Config.queue_for_job(Extra.TestJob) == "extra.queue1"
      assert Config.queue_for_job(Foo.High.TestJob) == "test.normal"
    end
  end
end
