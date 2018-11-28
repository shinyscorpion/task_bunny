defmodule TaskBunny.StatusTest do
  use ExUnit.Case, async: false

  import TaskBunny.QueueTestHelper
  alias TaskBunny.{Config, Queue, JobTestHelper}

  @host :status_test
  @queue "task_bunny.status_test"

  @supervisor :status_test_supervisor
  @worker_supervisor :status_test_worker_supervisor
  @publisher :status_test_publisher

  defp mock_config do
    worker = [host: @host, queue: @queue, concurrency: 1]

    :meck.new(Config, [:passthrough])
    :meck.expect(Config, :hosts, fn -> [@host] end)
    :meck.expect(Config, :connect_options, fn @host -> "amqp://localhost" end)
    :meck.expect(Config, :workers, fn(_any) -> [worker] end)
  end

  setup do
    clean(Queue.queue_with_subqueues(@queue))
    Queue.declare_with_subqueues(:default, @queue)

    mock_config()
    JobTestHelper.setup()
    TaskBunny.Supervisor.start_link(@supervisor, @worker_supervisor, @publisher)

    on_exit(fn ->
      :meck.unload()
    end)

    :ok
  end

  describe "status" do
    test "overview system up" do
      %{up: up} = TaskBunny.Status.overview(@supervisor)

      assert up
    end

    test "overview system down" do
      %{up: up} = TaskBunny.Status.overview(:fake_supervisor)

      refute up
    end

    test "overview workers" do
      %{workers: workers} = TaskBunny.Status.overview(@supervisor)

      assert length(workers) == 1
    end
  end
end
