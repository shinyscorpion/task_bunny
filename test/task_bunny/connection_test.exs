defmodule TaskBunny.ConnectionTest do
  use ExUnit.Case, async: false

  alias TaskBunny.{Connection, Config}

  setup do
    on_exit fn ->
      :meck.unload
    end
  end

  describe "get_connection" do
    test "returns AMQP connection" do
      {:ok, conn} = Connection.get_connection(:default)
      assert %AMQP.Connection{} = conn
    end

    test "returns error when connection is not available" do
      assert {:error, _} = Connection.get_connection(:foobar)
    end
  end

  describe "get_connection!" do
    test "raises ConnectError when connection is not available" do
      assert_raise Connection.ConnectError, fn ->
        Connection.get_connection!(:foobar)
      end
    end
  end

  describe "subscribe_connection" do
    test "sends connection to caller process" do
      ret = Connection.subscribe_connection(:default, self())
      assert ret == :ok
      assert_receive {:connected, %AMQP.Connection{}}
    end

    test "returns :error for invalid host" do
      ret = Connection.subscribe_connection(:foobar, self())
      assert ret == {:error, :invalid_host}
    end

    test "when the server has not established a connection" do
      :meck.new Config
      :meck.expect Config, :connect_options, fn (:foo) -> "amqp://localhost:1111" end

      {:ok, pid} = Connection.start_link(:foo)
      ret = Connection.subscribe_connection(:foo, self())

      # Trying to connect
      assert ret == :ok
      # Since the connect options is invalid, you won't get any message
      refute_receive {:connected, _}, 10

      # Now connection will be made and you will receive a message
      :meck.expect Config, :connect_options, fn (:foo) -> [] end
      send pid, :connect
      assert_receive {:connected, %AMQP.Connection{}}

      GenServer.stop(pid)
    end
  end

  describe "subscribe_connection!" do
    test "raises ConnectError for invalid host" do
      assert_raise Connection.ConnectError, fn ->
        Connection.subscribe_connection!(:foobar, self())
      end
    end
  end

  describe "when connection is lost" do
    test "exits the process" do
      # ...so that the supervisor can restart it
      :meck.new Config
      :meck.expect Config, :connect_options, fn (:foo) -> [] end

      {:ok, pid} = Connection.start_link(:foo)
      Process.unlink(pid)

      {:ok, conn} = Connection.get_connection(:foo)
      AMQP.Connection.close(conn)
      :timer.sleep(10)

      refute Process.alive?(pid)
    end
  end
end
