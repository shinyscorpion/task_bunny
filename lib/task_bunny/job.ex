defmodule TaskBunny.Job do
  @moduledoc """
  TODO: Write me
  """

  @callback perform(any) :: :ok | {:error, term}

  require Logger
  alias TaskBunny.{Config, Queue, Job, Message, Publisher}
  alias TaskBunny.{
    Publisher.PublishError, Connection.ConnectError, Job.QueueNotFoundError
  }

  defmacro __using__(_options \\ []) do
    quote do
      @behaviour Job

      @doc false
      @spec enqueue(any, keyword) :: :ok | {:error, any}
      def enqueue(payload, options \\ []) do
        TaskBunny.Job.enqueue(__MODULE__, payload, options)
      end

      @doc false
      @spec enqueue!(any, keyword) :: :ok | {:error, any}
      def enqueue!(payload, options \\ []) do
        TaskBunny.Job.enqueue!(__MODULE__, payload, options)
      end

      # Returns timeout (default 2 minutes).
      # Overwrite the method to change the timeout.
      @doc false
      @spec timeout() :: integer
      def timeout, do: 120_000

      # Retries 10 times in every 5 minutes in default.
      # You have to re-create the queue after you change retry_interval.
      @doc false
      @spec max_retry() :: integer
      def max_retry, do: 10

      @doc false
      @spec retry_interval(integer) :: integer
      def retry_interval(_failed_count), do: 300_000

      defoverridable [timeout: 0, max_retry: 0, retry_interval: 1]
    end
  end

  @doc """
  Enqueues a job with payload.
  """
  @spec enqueue(atom, any, keyword) :: :ok | {:error, any}
  def enqueue(job, payload, options \\ []) do
    enqueue!(job, payload, options)

  rescue
    e in [ConnectError, PublishError, QueueNotFoundError] -> {:error, e}
  end

  @doc """
  Similar to enqueue/3 but raises an exception on error.
  """
  @spec enqueue!(atom, any, keyword) :: :ok
  def enqueue!(job, payload, options \\ []) do
    queue_data = Config.queue_for_job(job) || []

    host = options[:host] || queue_data[:host] || :default
    {:ok, message} = Message.encode(job, payload)

    case options[:queue] || queue_data[:name] do
      nil -> raise QueueNotFoundError, job: job
      queue -> do_enqueue(host, queue, message)
    end
  end

  @spec do_enqueue(atom, String.t, String.t) :: :ok | {:error, any}
  defp do_enqueue(host, queue, message) do
    declare_queue(host, queue)
    Publisher.publish!(host, queue, message)
  end

  @spec declare_queue(atom, String.t) :: :ok
  defp declare_queue(host, queue) do
    Queue.declare_with_subqueues(host, queue)
    :ok
  catch
    :exit, e ->
      # Handles the error but we carry on...
      # It's highly likely caused by the options on queue declare don't match.
      # We carry on with error log.
      Logger.error "TaskBunny.job: Failed to declare queue for #{queue}. If you have changed the queue configuration, you have to delete the queue and create it again. Error: #{inspect e}"

      {:error, {:exit, e}}
  end
end
