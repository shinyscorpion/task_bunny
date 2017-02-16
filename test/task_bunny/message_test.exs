defmodule TaskBunny.MessageTest do
  use ExUnit.Case, async: true
  alias TaskBunny.Message

  defmodule NameJob do
    use TaskBunny.Job

    def perform(payload), do: {:ok, payload["name"]}
  end

  describe "encode/decode message body(payload)" do
    test "encode and decode payload" do
      encoded = Message.encode(NameJob, %{"name" => "Joe"})
      {:ok, %{"job" => job, "payload" => payload}} = Message.decode(encoded)
      assert job.perform(payload) == {:ok, "Joe"}
    end

    test "decode broken json" do
      message = "{aaa:bbb}"
      assert {:error, {:poison_decode_error, _}} = Message.decode(message)
    end

    test "decode wrong format" do
      message = "{\"foo\": \"bar\"}"
      assert {:error, {:decode_exception, _}} = Message.decode(message)
    end

    test "decode invalid job" do
      encoded = Message.encode(InvalidJob, %{"name" => "Joe"})
      assert {:error, :job_not_loaded} = Message.decode(encoded)
    end
  end

  describe "failed_count" do
    test "RabbitMQ 3.6 header" do
      meta = %{app_id: :undefined, cluster_id: :undefined, consumer_tag: "amq.ctag-6gbrfVhVEsg5UluIEagNcQ", content_encoding: :undefined, content_type: :undefined, correlation_id: :undefined, delivery_tag: 69, exchange: "", expiration: :undefined, headers: [{"x-death", :array, [table: [{"count", :long, 67}, {"exchange", :longstr, ""}, {"queue", :longstr, "dlx.retry"}, {"reason", :longstr, "expired"}, {"routing-keys", :array, [longstr: "dlx.retry"]}, {"time", :timestamp, 1484651945}], table: [{"count", :long, 67}, {"exchange", :longstr, ""},{"queue", :longstr, "dlx"}, {"reason", :longstr, "rejected"}, {"routing-keys", :array, [longstr: "dlx"]}, {"time", :timestamp, 1484651915}]]}], message_id: :undefined, persistent: true, priority: :undefined, redelivered: false, reply_to: :undefined, routing_key: "dlx",timestamp: :undefined, type: :undefined, user_id: :undefined}

      assert Message.failed_count(meta) == 67
    end

    test "RabbitMQ 3.4 header" do
      headers = [{"x-death", :array, [table: [{"reason", :longstr, "expired"}, {"queue", :longstr, "jobs.test_job.retry"}, {"time", :timestamp, 1487256438}, {"exchange", :longstr, ""}, {"routing-keys", :array, [longstr: "jobs.test_job.retry"]}], table: [{"reason", :longstr, "rejected"}, {"queue", :longstr, "jobs.test_job"}, {"time", :timestamp, 1487256438}, {"exchange", :longstr, ""}, {"routing-keys", :array, [longstr: "jobs.test_job"]}], table: [{"reason", :longstr, "expired"}, {"queue", :longstr, "jobs.test_job.retry"}, {"time", :timestamp, 1487256438}, {"exchange", :longstr, ""}, {"routing-keys", :array, [longstr: "jobs.test_job.retry"]}], table: [{"reason", :longstr, "rejected"}, {"queue", :longstr, "jobs.test_job"}, {"time", :timestamp, 1487256438}, {"exchange", :longstr, ""}, {"routing-keys", :array, [longstr: "jobs.test_job"]}], table: [{"reason", :longstr, "expired"}, {"queue", :longstr, "jobs.test_job.retry"}, {"time", :timestamp, 1487256438}, {"exchange", :longstr, ""}, {"routing-keys", :array, [longstr: "jobs.test_job.retry"]}], table: [{"reason", :longstr, "rejected"}, {"queue", :longstr, "jobs.test_job"}, {"time", :timestamp, 1487256438}, {"exchange", :longstr, ""}, {"routing-keys", :array, [longstr: "jobs.test_job"]}]]}]

      meta = %{app_id: :undefined, cluster_id: :undefined, consumer_tag: "amq.ctag-6gbrfVhVEsg5UluIEagNcQ", content_encoding: :undefined, content_type: :undefined, correlation_id: :undefined, delivery_tag: 69, exchange: "", expiration: :undefined, headers: headers, message_id: :undefined, persistent: true, priority: :undefined, redelivered: false, reply_to: :undefined, routing_key: "dlx",timestamp: :undefined, type: :undefined, user_id: :undefined}

      assert Message.failed_count(meta) == 3
    end
  end
end
