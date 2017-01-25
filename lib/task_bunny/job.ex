defmodule TaskBunny.Job do
  @default_job_namespace "jobs"

  @callback perform(any) :: :ok | {:error, term}

  defmacro __using__(job_options \\ []) do
    quote do
      @behaviour TaskBunny.Job
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

      def queue_name() do
        options = unquote(job_options)

        name = case Keyword.get(options, :id, nil) do
          nil -> Keyword.get(options, :full, false) |> module_queue_name
          id -> id
        end

        namespace = Keyword.get(options, :namespace, unquote(@default_job_namespace))

        "#{namespace}.#{name}"
      end

      def all_queues() do
        [
          queue_name(),
          TaskBunny.Queue.retry_queue_name(queue_name()),
          TaskBunny.Queue.failed_queue_name(queue_name())
        ]
      end

      def declare_queue(connection) do
        try do
          TaskBunny.Queue.declare_with_retry(
            connection, queue_name(), retry_interval: retry_interval()
          )
          :ok
        rescue
          e ->
            Logger.error "Failed to declare queue for #{queue_name()}. If you have changed the queue configuration, you have to delete the queue and create it again. Error: #{inspect e}"
            :error
        end
      end

      def delete_queue(connection) do
        TaskBunny.Queue.delete_with_retry(connection, queue_name())
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
