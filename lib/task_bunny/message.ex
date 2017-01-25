defmodule TaskBunny.Message do
  @moduledoc """
  Provides functionalities to access a message and its meta data.
  """

  @doc """
  Retrieves number of count the message was consumed and failed to process

  ## Example

    iex> meta = %{app_id: :undefined, cluster_id: :undefined, consumer_tag: "amq.ctag-6gbrfVhVEsg5UluIEagNcQ", content_encoding: :undefined, content_type: :undefined, correlation_id: :undefined, delivery_tag: 69, exchange: "", expiration: :undefined, headers: [{"x-death", :array, [table: [{"count", :long, 67}, {"exchange", :longstr, ""}, {"queue", :longstr, "dlx.retry"}, {"reason", :longstr, "expired"}, {"routing-keys", :array, [longstr: "dlx.retry"]}, {"time", :timestamp, 1484651945}], table: [{"count", :long, 67}, {"exchange", :longstr, ""},{"queue", :longstr, "dlx"}, {"reason", :longstr, "rejected"}, {"routing-keys", :array, [longstr: "dlx"]}, {"time", :timestamp, 1484651915}]]}], message_id: :undefined, persistent: true, priority: :undefined, redelivered: false, reply_to: :undefined, routing_key: "dlx",timestamp: :undefined, type: :undefined, user_id: :undefined}
      iex> TaskBunny.Message.failed_count(meta)
      67
  """
  @spec failed_count(meta :: map | tuple | any) :: integer
  def failed_count(meta)

  def failed_count(%{headers: :undefined}), do: 0

  def failed_count(%{headers: headers}) do
    x_death = Enum.find headers, fn ({key, _, _}) ->
      key == "x-death"
    end

    failed_count(x_death)
  end

  def failed_count({"x-death", :array, tables}) do
    tables
    |> Enum.map(fn({_, attributes}) ->
         count_attr = Enum.find attributes, fn ({key, _, _}) ->
           key == "count"
         end

         if count_attr do
           {_, _, count} = count_attr
           count
         else
           0
         end
       end)
    |> Enum.max(fn -> 0 end)
  end

  def failed_count(_), do: 0
end
