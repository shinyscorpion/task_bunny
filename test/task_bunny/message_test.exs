defmodule TaskBunny.MessageTest do
  use ExUnit.Case, async: true
  alias TaskBunny.Message

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
