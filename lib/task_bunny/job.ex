defmodule TaskBunny.Job do
  @moduledoc false
  @default_job_namespace "jobs"

  @callback perform(any) :: :ok | {:error, term}

  alias TaskBunny.{Queue, Job, SyncPublisher}

  defmacro __using__(job_options \\ []) do
    quote do
      @behaviour Job
      require Logger

      defp snake_case(name) do
        name
        |> String.replace(~r/([^.])([A-Z])/, "\\1_\\2")
        |> String.downcase
      end

      defp module_queue_name(true) do
        __MODULE__
        |> Atom.to_string
        |> String.replace_prefix("Elixir.", "")
        |> snake_case
      end

      defp module_queue_name(_) do
        __MODULE__
        |> Atom.to_string
        |> String.replace(~r/^.*?([^.]+)$/, "\\1") # Only end string that doesn't have a ".".
        |> snake_case
      end

      @spec queue_name :: String.t
      def queue_name do
        options = unquote(job_options)

        name = case Keyword.get(options, :id, nil) do
          nil -> options |> Keyword.get(:full, false) |> module_queue_name
          id -> id
        end

        namespace = Keyword.get(options, :namespace, unquote(@default_job_namespace))

        "#{namespace}.#{name}"
      end

      @spec enqueue(any) :: :ok | :failed
      def enqueue(host \\ :default, payload) do
        SyncPublisher.push(host, __MODULE__, payload)
      end

      @spec all_queues :: list(String.t)
      def all_queues do
        [
          queue_name(),
          Queue.retry_queue_name(queue_name()),
          Queue.rejected_queue_name(queue_name())
        ]
      end

      @spec declare_queue(%AMQP.Connection{}) :: :ok
      def declare_queue(connection) do
        Queue.declare_with_retry(
          connection, queue_name(), retry_interval: retry_interval()
        )
        :ok
      catch
        :exit, e ->
          # Handles the error but we carry on...
          # It's highly likely caused by the options on queue declare don't match.
          # e.g. retry interbval a.k.a message ttl in retry queue
          # We carry on with error log.
          Logger.error "failed to declare queue for #{queue_name()}. If you have changed the queue configuration, you have to delete the queue and create it again. Error: #{inspect e}"

          {:error, {:exit, e}}
      end

      @spec delete_queue(%AMQP.Connection{}) :: :ok
      def delete_queue(connection) do
        Queue.delete_with_retry(connection, queue_name())
      end

      @doc false
      # Returns timeout (default 2 minutes).
      # Overwrite the method to change the timeout.
      def timeout, do: 120_000

      # Retries 10 times in every 5 minutes in default.
      # You have to re-create the queue after you change retry_interval.
      def max_retry, do: 10
      def retry_interval, do: 300_000

      defoverridable [timeout: 0, max_retry: 0, retry_interval: 0]
    end
  end
end
