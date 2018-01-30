defmodule TaskBunny.Message do
  @moduledoc """
  Functions that work on TaskBunny messages.

  It's a semi private module used by Job or Worker.
  You shouldn't have to deal with it normally.

  However in case you need to encode/decode TaskBunny messages,
  this module will help.
  """
  alias TaskBunny.Message.DecodeError
  alias TaskBunny.JobError

  @doc """
  Encode message body in JSON with job and argument.
  """
  @spec encode(atom, any) :: {:ok, String.t}
  def encode(job, payload) do
    data = message_data(job, payload)
    Poison.encode(data, pretty: true)
  end

  @doc """
  Similar to encode/2 but raises an exception on error.
  """
  @spec encode!(atom, any) :: String.t
  def encode!(job, payload) do
    data = message_data(job, payload)
    Poison.encode!(data, pretty: true)
  end

  @spec message_data(atom, any) :: map
  defp message_data(job, payload) do
    %{
      "job" => encode_job(job),
      "payload" => payload,
      "created_at" => DateTime.utc_now()
    }
  end

  @doc """
  Decode message body in JSON to map data.
  """
  @spec decode(String.t) :: {:ok, map} | {:error, any}
  def decode(message) do
    case Poison.decode(message) do
      {:ok, decoded} ->
        job = decode_job(decoded["job"])
        if job && Code.ensure_loaded?(job) do
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
  Similar to decode/1 but raises an exception on error.
  """
  @spec decode!(String.t) :: map
  def decode!(message) do
    case decode(message) do
      {:ok, decoded} -> decoded
      {:error, {error_type, error}} ->
        raise DecodeError, type: error_type, body: message, error: error
      {:error, error_type} ->
        raise DecodeError, type: error_type, body: message
    end
  end

  @spec encode_job(atom) :: String.t
  defp encode_job(job) do
    job
    |> Atom.to_string
    |> String.trim_leading("Elixir.")
  end

  @spec decode_job(String.t) :: atom | nil
  defp decode_job(job_name) do
    job_name = if job_name =~ ~r/^Elixir\./ do
      job_name
    else
      "Elixir.#{job_name}"
    end

    try do
      String.to_existing_atom(job_name)
    rescue
      ArgumentError -> nil
    end
  end

  @doc """
  Add an error log to message body.
  """
  @spec add_error_log(String.t|map, JobError.t) :: String.t | map
  def add_error_log(message, error) when is_map(message) do
    error = %{
      "result" => JobError.get_result_info(error),
      "failed_at" => DateTime.utc_now(),
      "host" => host(),
      "pid" => inspect(self())
    }
    errors = (message["errors"] || []) |> List.insert_at(-1, error)
    Map.merge(message, %{"errors" => errors})
  end

  def add_error_log(raw_message, error) do
    raw_message
    |> Poison.decode!()
    |> add_error_log(error)
    |> Poison.encode!(pretty: true)
  end

  defp host do
    {:ok, hostname} = :inet.gethostname()
    List.to_string(hostname)
  end

  @doc """
  Returns a number of errors occurred for the message.
  """
  @spec failed_count(String.t|map) :: integer
  def failed_count(message) when is_map(message) do
    case message["errors"] do
      nil -> 0
      errors -> length(errors)
    end
  end

  def failed_count(raw_message) do
    raw_message
    |> Poison.decode!()
    |> failed_count()
  end
end
