defmodule TaskBunny.Status do
  @moduledoc ~S"""
  Modules that handles TaskBunny status.
  """

  alias TaskBunny.Status

  @typedoc ~S"""
  The Worker status contains the follow fields:
    - `version`, the current status version.
    - `up`, whether the `TaskBunny.Supervisor` is running.
    - `connected`, whether a connection to RabbitMQ has been made.
    - `workers`, list of worker statusses.
  """
  @type t :: %__MODULE__{version: String.t, up: boolean, connected: boolean, workers: list(TaskBunny.Status.Worker.t)}

  defstruct version: "1", up: true, connected: false, workers: []

  @doc ~S"""
  Returns TaskBunny status.
  """
  @spec overview(supervisor :: atom) :: Status.t
  def overview(supervisor \\ TaskBunny.Supervisor) do
    case supervisor_alive?(supervisor) do
      true ->
        %Status{
          up: true,
          connected: get_connection_status(),
          workers: get_workers_status(supervisor),
        }
      _ ->
        %Status{
          up: false,
          connected: get_connection_status(),
        }
    end
  end

  @spec get_connection_status() :: boolean
  defp get_connection_status do
    case TaskBunny.Connection.get_connection do
      nil -> false
      _ -> true
    end
  end

  @spec supervisor_alive?(supervisor :: atom) :: boolean
  defp supervisor_alive?(supervisor) do
    case Process.whereis(supervisor) do
      nil -> false
      pid -> Process.alive?(pid)
    end
  end

  @spec get_workers_status(supervisor :: atom) :: list(TaskBunny.Status.Worker.t)
  defp get_workers_status(supervisor) do
    supervisor
    |> Supervisor.which_children
    |> Enum.map(&get_worker_supervisor_status/1)
    |> List.flatten
  end

  @spec get_workers_status({TaskBunny.WorkerSupervisor, pid :: pid, atom, list()}) :: list(TaskBunny.Status.Worker.t)
  defp get_worker_supervisor_status({TaskBunny.WorkerSupervisor, pid, _atom, _list}) do
    pid
    |> Supervisor.which_children
    |> Enum.map(&Status.Worker.get/1)
  end

  @spec get_workers_status(any) :: []
  defp get_worker_supervisor_status(_) do
    []
  end
end