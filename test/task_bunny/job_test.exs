defmodule TaskBunny.JobTest do
  use ExUnit.Case

  alias TaskBunny.Job

  defmodule JobWithAllDefault do
    use Job
    def perform(_), do: nil
  end

  defmodule JobWithId do
    use Job, id: "frank"
    def perform(_), do: nil
  end

  defmodule JobWithNamespace do
    use Job, namespace: "frank"
    def perform(_), do: nil
  end

  defmodule JobWithFull do
    use Job, full: true
    def perform(_), do: nil
  end

  describe "queue_name" do
    test "has default name" do
      assert JobWithAllDefault.queue_name == "jobs.job_with_all_default"
    end

    test "has id" do
      assert JobWithId.queue_name == "jobs.frank"
    end

    test "has namespace" do
      assert JobWithNamespace.queue_name == "frank.job_with_namespace"
    end

    test "has full namespace" do
      assert JobWithFull.queue_name == "jobs.task_bunny.job_test.job_with_full"
    end
  end
end
