defmodule Mix.Tasks.TaskBunny.Queue.Reset do
  use Mix.Task

  @shortdoc "Reset all queues in config files"

  @moduledoc """
  Mix task to reset all queues.

  Please be aware it delete queues and recreate them.
  So all existing messages in the queues will go away.
  """

  alias TaskBunny.{Connection, Config}

  @doc false
  def run(_args) do
    Config.disable_auto_start()
    Mix.Task.run "app.start"

    _connections = Enum.map Config.hosts(), fn (host) ->
      Connection.start_link(host)
    end

    Config.jobs
    |> Enum.each(fn (job) -> reset_queue(job) end)
  end

  defp reset_queue(job_info) do
    Mix.shell.info "Resetting queues for #{inspect job_info}"

    conn = Connection.get_connection()
    job = job_info[:job]
    job.delete_queue(conn)
    job.declare_queue(conn)
  end
end
