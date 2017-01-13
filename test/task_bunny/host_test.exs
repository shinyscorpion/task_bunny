defmodule TaskBunny.HostTest do
  use ExUnit.Case

  setup do
    default_options = TaskBunny.Host.connect_options
    TaskBunny.Host.clear

    on_exit fn ->
      TaskBunny.Host.clear
      TaskBunny.Host.register default_options
    end
  end

  test "storing host information" do
    # default
    TaskBunny.Host.register(host: "localhost", port: 5672)
    # host 1
    TaskBunny.Host.register(:host1, "amqp://guest:guest@localhost:5672")
    # host 2
    TaskBunny.Host.register(:host2, host: "host2.example.com", port: 15672, username: "fran")

    assert TaskBunny.Host.connect_options == [host: "localhost", port: 5672]
    assert TaskBunny.Host.connect_options(:host1) == "amqp://guest:guest@localhost:5672"
    assert TaskBunny.Host.connect_options(:host2) == [host: "host2.example.com", port: 15672, username: "fran"]
  end
end
