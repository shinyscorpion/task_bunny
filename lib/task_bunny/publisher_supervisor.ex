defmodule TaskBunny.PublisherSupervisor do
  @moduledoc """
    Supervisor for the publisher
  """

  use Supervisor

  alias TaskBunny.PublisherWorker

  @doc """
    Starts the supervisor
  """
  @spec start_link(atom) :: {:ok, pid} | {:error, term}
  def start_link(_name \\ __MODULE__) do
    Supervisor.start_link(__MODULE__, :ok)
  end

  @doc """
    Initializes the supervisor with the poolboy publisher
  """
  @spec init(:ok) :: {:ok, {:supervisor.sup_flags(), [Supervisor.Spec.spec()]}} | :ignore
  def init(:ok) do
    children = [
      :poolboy.child_spec(:publisher, config())
    ]

    supervise(children, strategy: :one_for_one)
  end

  defp config do
    [
      {:name, {:local, :publisher}},
      {:worker_module, PublisherWorker},
      {:size, 15},
      {:max_overflow, 0}
    ]
  end
end
