defmodule Coelho.ConnectionTest do
  use ExUnit.Case, async: false

  describe "connection" do
    test "should reconnect to rabbitmq" do
      conn = Coelho.Connection.get()

      Process.exit(conn.pid, :killed)

      # :timer.sleep(1000)

      new_conn = Coelho.Connection.get()

      IO.inspect(conn)
      IO.inspect(new_conn)

      refute Process.alive?(conn.pid)
      assert Process.alive?(new_conn.pid)
    end
  end
end
