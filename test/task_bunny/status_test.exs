defmodule TaskBunny.StatusTest do
  use ExUnit.Case, async: false

  import TaskBunny.TestSupport.QueueHelper
  alias TaskBunny.Config
  alias TaskBunny.TestSupport.JobTestHelper
  alias TaskBunny.TestSupport.JobTestHelper.TestJob

  setup do
    clean [TestJob.queue_name]

    job = [
      job: TaskBunny.TestSupport.JobTestHelper.TestJob,
      concurrency: 3,
      host: :foo
    ]

    :meck.new Config, [:passthrough]
    :meck.expect Config, :hosts, fn -> [:foo] end
    :meck.expect Config, :connect_options, fn (:foo) -> "amqp://localhost" end
    :meck.expect Config, :jobs, fn -> [job] end

    JobTestHelper.setup

    {:ok, pid} = TaskBunny.Supervisor.start_link(:foo_supervisor)

    on_exit fn ->
      :meck.unload
      if Process.alive?(pid), do: Supervisor.stop(pid)
    end

    :ok
  end

  describe "status" do
    test "overview system up" do
      %{up: up} = TaskBunny.Status.overview(:foo_supervisor)

      assert up
    end

    test "overview system down" do
      %{up: up} = TaskBunny.Status.overview(:fake_supervisor)

      refute up
    end

    test "overview workers" do
      %{workers: workers} = TaskBunny.Status.overview(:foo_supervisor)

      assert length(workers) == 1
    end
  end
end