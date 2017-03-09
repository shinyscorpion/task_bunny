defmodule TaskBunny.Connection.ConnectError do
  @moduledoc """
  Raised when failed to retain a connection
  """
  defexception [:type, :message]

  @spec exception(keyword) :: map
  def exception(_opts = [type: type, host: host]) do
    title = "Failed to get a connection to host '#{host}':"
    detail = case type do
      :invalid_host ->
        "The host is not defined in config"
      :no_connection_process ->
        """
        No process running for the host connection.

        - Make sure supervisor process is up running.
        - You might try to get connection before the process is ready.
        """
      :not_connected ->
        """
        The connection is not available.

        - Check if RabbitMQ host is up running.
        - Make sure you can connect to RabbitMQ from the application host.
        - You might try to get connection before process is ready.
        """
    end

    message = "#{title}\n#{detail}"
    %__MODULE__{message: message, type: type}
  end
end
