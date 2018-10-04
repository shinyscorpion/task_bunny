defmodule TaskBunny.PublisherWorkerTest do
  use ExUnit.Case, async: false
  import TaskBunny.QueueTestHelper
  alias TaskBunny.{PublisherWorker, QueueTestHelper}

  @queue_name "task_bunny.test_queue"

  setup do
    clean([@queue_name])
    {:ok, server_pid} = PublisherWorker.start_link("foo")
    {:ok, server: server_pid}
  end

  describe "handle call/3 :publish" do
    test "publishes a message to a queue", %{server: server_pid} do
      QueueTestHelper.declare(@queue_name)
      GenServer.call(server_pid, {:publish, :default, "", @queue_name, "Hello Queue", []})

      {message, _} = QueueTestHelper.pop(@queue_name)
      assert message == "Hello Queue"
    end

    test "returns ok if the publication was possible", %{server: server_pid} do
      QueueTestHelper.declare(@queue_name)

      assert :ok =
               GenServer.call(
                 server_pid,
                 {:publish, :default, "", @queue_name, "Hello Queue", []}
               )
    end

    test "returns the error if there was an error while publishing", %{server: server_pid} do
      {:error, :invalid_host} =
        GenServer.call(server_pid, {:publish, :invalid, "", @queue_name, "Hello Queue", []})
    end
  end
end
