defmodule TaskBunny.TestSupport.JobTestHelper do
  defmodule Tracer do
    def performed(_), do: nil
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
  end

  def wait_for_perform(number \\ 1) do
    Enum.find_value 1..100, fn (v) ->
      history = :meck.history(Tracer)
      if length(history) >= number do
        true
      else
        :timer.sleep(10)
        false
      end
    end || false
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
end
