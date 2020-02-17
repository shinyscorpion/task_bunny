defmodule TaskBunny.ConfigError do
  @moduledoc """
  Raised when an error was found on TaskBunny config
  """
  defexception [:message]

  def exception(message: message) do
    title = "Failed to load TaskBunny config"
    message = "#{title}\n#{message}"
    %__MODULE__{message: message}
  end
end

defmodule TaskBunny.Connection.ConnectError do
  @moduledoc """
  Raised when failed to retain a connection
  """
  defexception [:type, :message]

  def exception(_opts = [type: type, host: host]) do
    title = "Failed to get a connection to host '#{host}'."

    detail =
      case type do
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

        fallback ->
          "#{fallback}"
      end

    message = "#{title}\n#{detail}"
    %__MODULE__{message: message, type: type}
  end
end

defmodule TaskBunny.Job.QueueNotFoundError do
  @moduledoc """
  Raised when failed to find a queue for the job.
  """
  defexception [:job, :message]

  def exception(job: job) do
    title = "Failed to find a queue for the job."
    detail = "job=#{job}"

    message = "#{title}\n#{detail}"
    %__MODULE__{message: message, job: job}
  end
end

defmodule TaskBunny.Message.DecodeError do
  @moduledoc """
  Raised when failed to decode the message.
  """
  defexception [:message]

  def exception(opts) do
    title = "Failed to decode the message."

    detail =
      case opts[:type] do
        :job_not_loaded ->
          "Job is not valid Elixir module"

        :decode_error ->
          "Failed to decode the message. error=#{inspect(opts[:error])}"

        fallback ->
          "#{fallback}"
      end

    message = "#{title}\n#{detail}\nmessage body=#{opts[:body]}"
    %__MODULE__{message: message}
  end
end

defmodule TaskBunny.Publisher.PublishError do
  @moduledoc """
  Raised when failed to publish the message.
  """
  defexception [:message, :inner_error]

  def exception(inner_error: inner_error) do
    title = "Failed to publish the message."
    detail = "error=#{inspect(inner_error)}"

    message = "#{title}\n#{detail}"
    %__MODULE__{message: message, inner_error: inner_error}
  end
end
