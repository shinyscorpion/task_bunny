defmodule TaskBunny.Message do
  @moduledoc """
  Functions to access messages and its meta data.
  """

  @doc """
  Encode message body in JSON with job and arugment.
  """
  @spec encode(atom, any) :: String.t
  def encode(job, payload) do
    %{
      "job" => job_to_string(job),
      "payload" => payload,
      "created_at" => DateTime.utc_now()
    }
    |> Poison.encode!
  end

  @doc """
  Decode message body in JSON to map
  """
  @spec decode(String.t) :: map
  def decode(message) do
    case Poison.decode(message) do
      {:ok, decoded} ->
        job = string_to_job(decoded["job"])
        if Code.ensure_loaded?(job) do
          {:ok, %{decoded | "job" => job}}
        else
          {:error, :job_not_loaded}
        end
      error ->
        {:error, {:poison_decode_error, error}}
    end
  rescue
    error -> {:error, {:decode_exception, error}}
  end

  @doc """
  Retrieves number of count the message was consumed and failed to process

  ## Example

      iex> meta = %{app_id: :undefined, cluster_id: :undefined, consumer_tag: "amq.ctag-6gbrfVhVEsg5UluIEagNcQ", content_encoding: :undefined, content_type: :undefined, correlation_id: :undefined, delivery_tag: 69, exchange: "", expiration: :undefined, headers: [{"x-death", :array, [table: [{"count", :long, 67}, {"exchange", :longstr, ""}, {"queue", :longstr, "dlx.retry"}, {"reason", :longstr, "expired"}, {"routing-keys", :array, [longstr: "dlx.retry"]}, {"time", :timestamp, 1484651945}], table: [{"count", :long, 67}, {"exchange", :longstr, ""},{"queue", :longstr, "dlx"}, {"reason", :longstr, "rejected"}, {"routing-keys", :array, [longstr: "dlx"]}, {"time", :timestamp, 1484651915}]]}], message_id: :undefined, persistent: true, priority: :undefined, redelivered: false, reply_to: :undefined, routing_key: "dlx",timestamp: :undefined, type: :undefined, user_id: :undefined}
      iex> TaskBunny.Message.failed_count(meta)
      67
  """
  @spec failed_count(map | tuple | any) :: integer
  def failed_count(meta)

  def failed_count(%{headers: :undefined}), do: 0

  def failed_count(%{headers: headers}) do
    x_death = Enum.find headers, fn ({key, _, _}) ->
      key == "x-death"
    end

    failed_count(x_death)
  end

  def failed_count({"x-death", :array, tables}) do
    count =
      tables
      |> Enum.map(fn({_, attributes}) ->
           count_attr = Enum.find attributes, fn ({key, _, _}) ->
             key == "count"
           end

           case count_attr do
             {_, _, count} -> count
             _ -> 0
           end
         end)
      |> Enum.max(fn -> 0 end)

    if count > 0, do: count, else: failed_count_pre_3_6(tables)
  end

  def failed_count(_), do: 0

  # Priort to 3.6, it doesn't contain count information.
  # We need to count it up by ourselves.
  @spec failed_count_pre_3_6(list) :: integer
  defp failed_count_pre_3_6(tables) do
    # List up queues
    queues =
      tables
      |> Enum.map(fn ({_, tuples}) ->
        tuple = Enum.find(tuples, fn ({key, _type, _value}) ->
          key == "queue"
        end)
        case tuple do
          {_, _, queue_name} -> queue_name
          _ -> nil
        end
      end)
      |> Enum.filter(fn (queue) -> queue end)

    # Count up queues
    # ["jobs.a.retry", "jobs.a", "jobs.a.retry", "jobs.a"]
    # => %{"jobs.a.retry" => 2, "jobs.a" => 2}
    # => then takes the max value

    queues
    |> Enum.reduce(%{}, fn (queue, counts) ->
      if counts[queue] do
        %{counts | queue => counts[queue] + 1}
      else
        Map.merge(counts, %{queue => 1})
      end
    end)
    |> Map.to_list
    |> Enum.map(fn ({_q, count}) -> count end)
    |> Enum.max
  end

  # Turns a job(module/atom) into a String
  #
  # So:
  #   Jobs.Example => "Jobs.Example"
  def job_to_string(job) do
    job
    |> Atom.to_string
    |> String.trim_leading("Elixir.")
  end

  # Turns Strings into job(module) names
  #
  # So:
  #   "Elixir.Jobs.Example" => Jobs.Example
  #   "Jobs.Example" => Jobs.Example
  #   "elixir.jobs.example" => Jobs.Example
  #   "jobs.example" => Jobs.Example
  def string_to_job(job) do
    job
    |> String.split(".")
    |> Enum.map(&capitalize/1)
    |> Enum.map(&String.to_atom/1)
    |> Module.concat
  end

  # Capitialize the first letter, but leave other capital letters alone
  defp capitalize(string) do
    string
    |> String.split_at(1)
    |> (fn {head, tail} -> String.upcase(head) <> tail end).()
  end
end
