defmodule TaskBunny.ConnectionTest do
  use ExUnit.Case, async: false

  alias TaskBunny.Connection

  describe "open" do
    test "returns a connection" do
      assert Connection.open()
    end
  end

  describe "close" do
    test "closes a connection" do
      Connection.open()

      assert Connection.close() == :ok
    end
  end

  describe "subscribe" do
    test "sends a message on connect" do
      Connection.subscribe()

      assert_receive {:connection, _}, 5000
    end

    test "sends a message on disconnect" do
      Connection.subscribe()

      AMQP.Connection.close(Connection.open())

      assert_receive {:connection, _}, 5000
      assert_receive :no_connection, 5000
    end

    test "sends a message on reconnect" do
      Connection.subscribe()

      AMQP.Connection.close(Connection.open())

      assert_receive {:connection, _}, 5000
      assert_receive :no_connection, 5000
      assert_receive {:connection, _}, 5000
    end
  end
end
