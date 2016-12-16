defmodule TaskBunny.Job do
  @default_job_namespace "jobs"

  @callback perform(any) :: :ok | {:error, term}

  defmacro __using__(job_options \\ []) do
    quote do
      @behaviour TaskBunny.Job

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
    end
  end
end