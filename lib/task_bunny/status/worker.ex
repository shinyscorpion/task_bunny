defmodule TaskBunny.Status.Worker do
  @moduledoc false
  # Functions that handles the Worker status.
  #
  # This module is private to TaskBunny.
  # It's aimed to provide useful stats to Wobserver integration.
  #

  @typedoc ~S"""
  The Worker status contains the follow fields:
    - `queue`, the name of queue the worker is listening to.
    - `runners`, the amount of runners currently running the `Job`.
    - `channel`, the connected channel with consumer tag or false if not connected.
    - `stats`, the amount of failed and succeeded jobs.
  """
  @type t :: %__MODULE__{
          queue: String.t(),
          runners: integer,
          channel: false | String.t(),
          consuming: boolean,
          stats: %{
            failed: integer,
            succeeded: integer,
            rejected: integer
          }
        }

  @enforce_keys [:queue]
  defstruct queue: nil,
            runners: 0,
            channel: false,
            consuming: false,
            stats: %{
              failed: 0,
              succeeded: 0,
              rejected: 0
            }

  @doc ~S"""
  Returns the Worker status.
  """
  @spec get({any, pid, atom, list}) :: TaskBunny.Status.Worker.t()
  def get({_name, pid, _atom, _list}) do
    get(pid)
  end

  @spec get(pid) :: TaskBunny.Status.Worker.t()
  def get(pid) do
    GenServer.call(pid, :status)
  end
end
