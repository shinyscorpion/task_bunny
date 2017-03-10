defmodule Mix.Tasks.TaskBunny.Queue.Reset do
  use Mix.Task

  @shortdoc "Reset all queues in config files"

  @moduledoc """
  Mix task to reset all queues.

  What it does is that deletes the queues and creates them again.
  Therefore all messages in the queues will go away.
  """

  alias TaskBunny.{Connection, Config, Queue}

  @doc false
  @spec run(list) :: any
  def run(_args) do
    Config.disable_auto_start()
    Mix.Task.run "app.start"

    _connections = Enum.map Config.hosts(), fn (host) ->
      Connection.start_link(host)
    end

    Config.queues
    |> Enum.each(fn (queue) -> reset_queue(queue) end)
  end

  defp reset_queue(queue) do
    Mix.shell.info "Resetting queues for #{inspect queue}"
    host = queue[:host] || :default

    Queue.delete_with_subqueues(host, queue[:name])
    Queue.declare_with_subqueues(host, queue[:name])
  end
end
