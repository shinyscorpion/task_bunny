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

  @doc """
  Returns jobs in config.
  """
  @spec jobs :: [keyword]
  def jobs do
    :task_bunny
    |> Application.get_all_env
    |> Enum.filter(fn ({key, _}) ->
         is_atom(key) && Atom.to_string(key) =~ ~r/jobs$/
       end)
    |> Enum.flat_map(fn ({_, job_list}) -> job_list end)
  end

  @doc """
  Returns if auto start is enabled.
  """
  @spec auto_start? :: boolean
  def auto_start? do
    case Application.fetch_env(:task_bunny, :disable_auto_start) do
      {:ok, true} -> false
      _ -> true
    end
  end

  @doc """
  Disable auto start manually
  """
  @spec disable_auto_start :: :ok
  def disable_auto_start do
    :ok = Application.put_env(:task_bunny, :disable_auto_start, true)
  end

  @spec hosts_config() :: list
  defp hosts_config do
    case Application.fetch_env(:task_bunny, :hosts) do
      {:ok, host_list} -> host_list
      _ -> []
    end
  end
end
