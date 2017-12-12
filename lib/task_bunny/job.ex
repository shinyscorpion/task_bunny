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

  By default TaskBunny terminates the job when it takes more than 2 minutes.
  This prevents messages blocking a worker.

  If your job is expected to take longer than 2 minutes or you want to terminate
  the job earlier, override `timeout/0`.

      defmodule SlowJob do
        use TaskBunny.Job

        def timeout, do: 300_000

        def perform(_) do
          slow_work()
          :ok
        end
      end

  # Retry

  By default TaskBunny retries 10 times every five minutes for a failed job.
  You can change this by overriding `max_retry/0` and `retry_interval/1`.

  For example, if you want the job to be retried five times and gradually
  increase the interval based on failed times, you can write logic like
  the following:

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

  @doc """
  Callback to process a job.

  It can take any type of argument as long as it can be serialized with Poison,
  but we recommend you to use map with string keys for a consistency.

      def perform(name) do
        IO.puts name <> ", it's not a preferred way"
      end

      def perform(%{"name" => name}) do
        IO.puts name <> ", it's a preferred way :)"
      end

  """
  @callback perform(any) :: :ok | {:ok, any} | {:error, term}

  @doc """
  Callback for the timeout in milliseconds for a job execution.

  Default value is 120_000 = 2 minutes.
  Override the function if you want to change the value.
  """
  @callback timeout() :: integer

  @doc """
  Callback for the max number of retries TaskBunny can make for a failed job.

  Default value is 10.
  Override the function if you want to change the value.
  """
  @callback max_retry() :: integer

  @doc """
  Callback for the retry interval in milliseconds.

  Default value is 300_000 = 5 minutes.
  Override the function if you want to change the value.

  TaskBunny will set failed count to the argument.
  The value will be more than or equal to 1 and less than or equal to max_retry.
  """
  @callback retry_interval(integer) :: integer

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
      # Override the method to change the timeout.
      @doc false
      @spec timeout() :: integer
      def timeout, do: 120_000

      # Retries 10 times in every 5 minutes by default.
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

  - delay: Set time in milliseconds to schedule the job enqueue time.
  - host: RabbitMQ host. By default it is automatically selected from configuration.
  - queue: RabbitMQ queue. By default it is automatically selected from configuration.
  - reply_to: sets the reply_to header and responds to that queue with the outcome of the job
  - correlation_id: sets a cerrelation ID that can be used to match jobs on the client side

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
      queue -> do_enqueue(host, queue, message, map_options(options))
    end
  end

  @spec do_enqueue(atom, String.t, String.t, Map.t) :: :ok | {:error, any}
  defp do_enqueue(host, queue, message, %{expiration: _delay} = options) do
    scheduled = Queue.scheduled_queue(queue)
    Publisher.publish!(host, scheduled, message, Map.to_list(options))
  end
  defp do_enqueue(host, queue, message, options) do
    Publisher.publish!(host, queue, message, Map.to_list(options))
  end

  # explicitly map options to make sure we only have approved data in our
  # messages
  defp map_options(options) do
    %{}
    |> add_delay(options)
    |> add_reply_to(options)
    |> add_corr_id(options)
    |> add_app_id(options)
  end
  defp add_delay(map, options) do
    case options[:delay] do
      nil -> map
      delay -> Map.merge(map, %{expiration: delay})
    end
  end
  defp add_reply_to(map, options) do
    case options[:reply_to] do
      nil -> map
      queue -> Map.merge(map, %{reply_to: queue})
    end
  end
  defp add_corr_id(map, options) do
    case options[:correlation_id] do
      nil -> map
      id -> Map.merge(map, %{correlation_id: id})
    end
  end
  defp add_app_id(map, options) do
    case options[:app_id] do
      nil -> map
      id -> Map.merge(map, %{app_id: id})
    end
  end

end
