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
      Tracer.performed(payload)

      if payload["sleep"], do: :timer.sleep(payload["sleep"])

      cond do
        payload["reject"] -> :reject
        payload["fail"] -> :error
        true -> :ok
      end
    end

    def retry_interval(_), do: RetryInterval.interval()

    def on_start(body) do
      pid = enqueuer_pid(body)
      pid && send(pid, :on_start_callback_called)
      :ok
    end

    def on_success(body) do
      pid = enqueuer_pid(body)
      pid && send(pid, :on_success_callback_called)
      :ok
    end

    def on_retry(body) do
      pid = enqueuer_pid(body)
      pid && send(pid, :on_retry_callback_called)
      :ok
    end

    def on_reject(body) do
      pid = enqueuer_pid(body)
      pid && send(pid, :on_reject_callback_called)
      :ok
    end

    defp enqueuer_pid(body) do
      ppid =
        body
        |> Poison.decode!()
        |> get_in(["payload", "ppid"])

      ppid && ppid |> Base.decode64!() |> :erlang.binary_to_term()
    end
  end

  def wait_for_perform(number \\ 1) do
    performed =
      Enum.find_value(
        1..100,
        fn _ ->
          history = :meck.history(Tracer)

          if length(history) >= number do
            true
          else
            :timer.sleep(10)
            false
          end
        end || false
      )

    # wait for the last message handled
    :timer.sleep(20)
    performed
  end

  def performed_payloads do
    :meck.history(Tracer)
    |> Enum.map(fn {_, {_, _, args}, _} -> List.first(args) end)
  end

  def performed_count do
    length(:meck.history(Tracer))
  end

  def setup do
    :meck.new(Tracer)
    :meck.expect(Tracer, :performed, fn _ -> nil end)
  end

  def teardown do
    :meck.unload()
  end

  def wait_for_connection(host) do
    Enum.find_value(
      1..100,
      fn _ ->
        case TaskBunny.Connection.subscribe_connection(host, self()) do
          :ok ->
            true

          _ ->
            :timer.sleep(10)
            false
        end
      end || raise("connection process is not up")
    )

    receive do
      {:connected, conn} -> conn
    after
      1_000 -> raise "failed to connect to #{host}"
    end
  end
end
