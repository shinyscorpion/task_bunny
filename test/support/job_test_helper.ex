defmodule TaskBunny.JobTestHelper do
  defmodule Tracer do
    def performed(_), do: nil
  end

  defmodule RetryInterval do
    def interval, do: 60_000
  end

  defmodule TestJob do
    use TaskBunny.Job

    def perform(payload) do
      Tracer.performed payload

      if payload["sleep"], do: :timer.sleep(payload["sleep"])

      if payload["fail"] do
        :error
      else
        :ok
      end
    end

    def retry_interval(_), do: RetryInterval.interval()
  end

  def wait_for_perform(number \\ 1) do
    performed = Enum.find_value 1..100, fn (_) ->
      history = :meck.history(Tracer)
      if length(history) >= number do
        true
      else
        :timer.sleep(10)
        false
      end
    end || false

    :timer.sleep(20) # wait for the last message handled
    performed
  end

  def performed_payloads do
    :meck.history(Tracer)
    |> Enum.map(fn ({_, {_, _, args}, _}) -> List.first(args) end)
  end

  def performed_count do
    length :meck.history(Tracer)
  end

  def setup do
    :meck.new Tracer
    :meck.expect Tracer, :performed, fn (_) -> nil end
  end

  def teardown do
    :meck.unload
  end

  def wait_for_connection(host) do
    Enum.find_value 1..100, fn (_) ->
      case TaskBunny.Connection.monitor_connection(host, self()) do
        :ok -> true
        _ ->
          :timer.sleep(10)
          false
      end
    end || raise "connection process is not up"

    receive do
      {:connected, conn} -> conn
    after
      1_000 -> raise "failed to connect to #{host}"
    end
  end
end
