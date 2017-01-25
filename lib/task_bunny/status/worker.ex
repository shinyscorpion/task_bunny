defmodule TaskBunny.Status.Worker do
  @moduledoc ~S"""
  Modules that handles the Worker status.
  """

  @typedoc ~S"""
  The Worker status contains the follow fields:
    - `job`, the `Job` for the `Worker`.
    - `runners`, the amount of runners currently running the `Job`.
    - `channel`, the connected channel with consumer tag or false if not connected.
    - `stats`, the amount of failed and succeeded jobs.
  """
  @type t :: %__MODULE__{
    job: atom,
    runners: integer,
    channel: false | String.t,
    stats: %{
      failed: integer,
      succeeded: integer,
      rejected: integer,
    },
  }

  @enforce_keys [:job]
  defstruct [
    :job,
    runners: 0,
    channel: false,
    stats: %{
      failed: 0,
      succeeded: 0,
      rejected: 0,
    },
  ]

  @doc ~S"""
  Returns the Worker status.
  """
  @spec get({any, pid :: pid, atom, list}) :: TaskBunny.Status.Worker.t
  def get({_name, pid, _atom, _list}) do
    get(pid)
  end

  @spec get(pid :: pid) :: TaskBunny.Status.Worker.t
  def get(pid) do
    GenServer.call(pid, :status)
  end
end