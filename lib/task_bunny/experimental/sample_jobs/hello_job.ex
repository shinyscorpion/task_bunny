defmodule TaskBunny.Experimental.SampleJobs.HelloJob do

  use TaskBunny.Job
  require Logger

  def perform(%{"name" => name}) do
    Logger.info "Hello #{name}!"

    :ok
  end
end
