defmodule TaskBunny.Config do
  @moduledoc """
  Modules that help you access to TaskBunny config values
  """

  @doc """
  Returns list of hosts in config.
  """
  @spec hosts :: [atom]
  def hosts do
    hosts_config()
    |> Enum.map(fn ({host, _options}) -> host end)
  end

  @doc """
  Returns connect options for the host. It raises an error if the host is not found.
  """
  @spec connect_options(host :: atom) :: list | String.t
  def connect_options(host) do
    hosts_config()[host][:connect_options] || raise "Can not find host '#{host}' in config"
  end

  @spec hosts_config() :: list
  defp hosts_config do
    case Application.fetch_env(:task_bunny, :hosts) do
      {:ok, hosts} -> hosts
      _ -> []
    end
  end
end
