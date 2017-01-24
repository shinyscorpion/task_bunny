defmodule TaskBunny.Experimental.Config do

  # Returns hosts
  def hosts do
    hosts_config()
    |> Enum.map(fn ({host, _options}) -> host end)
  end

  def connect_options(host) do
    hosts_config()[host][:connect_options] || raise "Can not find host '#{host}' in config"
  end

  defp hosts_config do
    case Application.fetch_env(:task_bunny, :hosts) do
      {:ok, hosts} -> hosts
      _ -> []
    end
  end
end
