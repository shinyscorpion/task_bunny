defmodule TaskBunny.JobError do
  @moduledoc """
  A struct that holds an error information occured at the job execution.
  """

  @type t :: %__MODULE__{
    job: atom,
    payload: any,
    raw_body: String.t,
    meta: map,
    error_type: :exception | :return_value | :timeout | :exit | nil,
    exception: struct | nil,
    stacktrace: list(tuple) | nil,
    reason: any
  }

  defstruct [
    job: nil,
    payload: nil,
    raw_body: "",
    meta: %{},
    error_type: nil,
    exception: nil,
    stacktrace: nil,
    return_value: nil,
    reason: nil
  ]

  @doc false
  def handle_exception(job, payload, exception) do
    %__MODULE__{
      job: job,
      payload: payload,
      error_type: :exception,
      exception: exception,
      stacktrace: System.stacktrace()
    }
  end

  @doc false
  def handle_exit(job, payload, reason) do
    %__MODULE__{
      job: job,
      payload: payload,
      error_type: :exit,
      reason: reason
    }
  end

  @doc false
  def handle_return_value(job, payload, return_value) do
    %__MODULE__{
      job: job,
      payload: payload,
      error_type: :return_value,
      return_value: return_value
    }
  end

  @doc false
  def handle_timeout(job, payload) do
    %__MODULE__{
      job: job,
      payload: payload,
      error_type: :timeout
    }
  end
end
