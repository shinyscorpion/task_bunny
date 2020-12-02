defmodule TaskBunny.MessageTest do
  use ExUnit.Case, async: true
  alias TaskBunny.{Message, JobError}

  defmodule NameJob do
    use TaskBunny.Job

    def perform(payload), do: {:ok, payload["name"]}
  end

  describe "encode/decode message body(payload)" do
    test "encode and decode payload" do
      {:ok, encoded} = Message.encode(NameJob, %{"name" => "Joe"})
      {:ok, %{"job" => job, "payload" => payload}} = Message.decode(encoded)
      assert job.perform(payload) == {:ok, "Joe"}
    end

    test "decode broken json" do
      message = "{aaa:bbb}"
      assert {:error, {:jason_decode_error, _}} = Message.decode(message)
    end

    test "decode wrong format" do
      message = "{\"foo\": \"bar\"}"
      assert {:error, {:decode_exception, _}} = Message.decode(message)
    end

    test "decode invalid job" do
      encoded = Message.encode!(InvalidJob, %{"name" => "Joe"})
      assert {:error, :job_not_loaded} == Message.decode(encoded)
    end

    test "decode invalid atom" do
      message =
        "{\"payload\": \"\",\"job\":\"Hello.Message\",\"created_at\":\"2017-02-17T10:14:13.149734Z\"}"

      assert {:error, :job_not_loaded} == Message.decode(message)
    end
  end

  describe "add_error_log" do
    @tag timeout: 1000
    test "adds error information to the message" do
      message = Message.encode!(NameJob, %{"name" => "Joe"})

      error = %JobError{
        error_type: :return_value,
        return_value: {:error, :test_error},
        failed_count: 0,
        stacktrace: Process.info(self(), :current_stacktrace),
        raw_body: "abcdefg"
      }

      new_message = Message.add_error_log(message, error)
      {:ok, %{"errors" => [added | _]}} = Message.decode(new_message)

      assert added["result"]["error_type"] == ":return_value"
      assert added["result"]["return_value"] == "{:error, :test_error}"
      refute added["result"]["raw_body"]
    end
  end
end
