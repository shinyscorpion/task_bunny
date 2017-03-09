defmodule TaskBunny.Job do
  @moduledoc false

  @callback perform(any) :: :ok | {:error, term}

  alias TaskBunny.{Config, Queue, Job, Message, Publisher}

  defmacro __using__(_options \\ []) do
    quote do
      @behaviour Job
      require Logger

      @spec enqueue(any, keyword) :: :ok | {:error, any}
      def enqueue(payload, options \\ []) do
        queue_data = Config.queue_for_job(__MODULE__)

        queue = options[:queue] || queue_data[:name]
        host = options[:host] || queue_data[:host] || :default
        message = Message.encode(__MODULE__, payload)

        do_enqueue(host, queue, message)
      end

      # TODO: enqueue!
      # custom errors

      @spec do_enqueue(atom, String.t|nil, String.t) :: :ok | {:error, any}
      defp do_enqueue(host, nil, message) do
        {:error, "Can't find a queue for #{__MODULE__}"}
      end

      defp do_enqueue(host, queue, message) do
        declare_queue(host, queue)
        Publisher.publish(host, queue, message)
      end

      @spec declare_queue(atom, String.t) :: :ok
      defp declare_queue(host, queue) do
        Queue.declare_with_subqueues(host, queue)
        :ok
      catch
        :exit, e ->
          # Handles the error but we carry on...
          # It's highly likely caused by the options on queue declare don't match.
          # e.g. retry interbval a.k.a message ttl in retry queue
          # We carry on with error log.
          Logger.error "failed to declare queue for #{queue}. If you have changed the queue configuration, you have to delete the queue and create it again. Error: #{inspect e}"

          {:error, {:exit, e}}
      end

      @doc false
      # Returns timeout (default 2 minutes).
      # Overwrite the method to change the timeout.
      def timeout, do: 120_000

      # Retries 10 times in every 5 minutes in default.
      # You have to re-create the queue after you change retry_interval.
      def max_retry, do: 10
      def retry_interval(_failed_count), do: 300_000

      defoverridable [timeout: 0, max_retry: 0, retry_interval: 1]
    end
  end

  # TODO: documentation
end
