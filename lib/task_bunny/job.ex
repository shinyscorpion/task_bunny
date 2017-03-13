defmodule TaskBunny.Job do
  @moduledoc """
  Behaviour module for implementing a TaskBunny job.

  TaskBunny job is an asynchronous background job whose execution request is
  enqueued to RabbitMQ and performed in a worker process.

      defmodule HelloJob do
        use TaskBunny.Job

        def perform(%{"name" => name}) do
          IO.puts "Hello " <> name

          :ok
        end
      end

      HelloJob.enqueue(%{"name" => "Cloud"})

  ## Failing

  TaskBunny treats the job as failed when...

  - the return value of perform is not `:ok` or `{:ok, something}`
  - the perform timed out
  - the perform raises an exception while being executed
  - the perform throws :exit signal while being executed.

  TaskBunny will retry the failed job later.

  ## Timeout

  In default, TaskBunny terminates the job when it takes more than 2 minutes.
  This helps you to avoid messages stuck in your queue.

  If your job is expected to take longer than 2 minutes or you want to terminate
  the job earlier, overwrite `timeout/0` function.

      defmodule SlowJob do
        use TaskBunny.Job

        def timeout, do: 300_000

        def perform(_) do
          slow_work()
          :ok
        end
      end

  # Retry

  In default, TaskBunny retries 10 times every five minutes for a failed job.
  You can change the behavior by overwriting `max_retry/0` and `retry_interval/1`.

  For example, if you want the job to be retried five times and gradually
  increase the inteval based on failed times, you can write the logic like
  the following.

      defmodule HttpSyncJob do
        def max_retry, do: 5

        def retry_interval(failed_count) do
          [1, 5, 10, 30, 60]
          |> Enum.map(&(&1 * 60_000))
          |> Enum.at(failed_count - 1, 1000)
        end

        ...
      end

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

  You might want to use the shorter version if you can access to the job.

      # Following two calls are exactly same.
      RegistrationJob.enqueue(payload)
      TaskBunny.enqueue(RegistrationJob, payload)

  ## Options

  - host: RabbitMQ host. In default, it's automatically selected from configuration.
  - queue: RabbitMQ queue. In default, It's automattically selected from configuration.

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
