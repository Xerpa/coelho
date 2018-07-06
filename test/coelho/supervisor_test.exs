defmodule Coelho.SupervisorTest do
  use ExUnit.Case, async: false

  setup do
    {:ok, supervisor} = Coelho.Supervisor.start_link([])

    on_exit(fn ->
      try do
        GenServer.stop(supervisor)
      rescue
        _ -> :ok
      catch
        _, _ -> :ok
      end
    end)

    {:ok, supervisor: supervisor}
  end

  describe "connection" do
    test "should reconnect to rabbitmq", %{supervisor: supervisor} do
      {:ok, conn} = Coelho.Supervisor.get_connection(supervisor)

      Process.exit(conn.pid, :kill)

      # :timer.sleep(1000)

      {:ok, new_conn} = Coelho.Supervisor.get_connection(supervisor)

      IO.inspect(conn)
      IO.inspect(new_conn)

      refute Process.alive?(conn.pid)
      assert Process.alive?(new_conn.pid)
    end
  end

  describe "managed channel" do
    test "opens a new managed channel", %{supervisor: supervisor} do
      assert {:ok, %AMQP.Channel{} = chan} = Coelho.Supervisor.get_managed_channel(supervisor)
    end

    test "returns the same channel if already open", %{supervisor: supervisor} do
      assert {:ok, chan1} = Coelho.Supervisor.get_managed_channel(supervisor)
      assert {:ok, chan2} = Coelho.Supervisor.get_managed_channel(supervisor)
      assert chan1.pid == chan2.pid
    end

    test "links the channel to the caller process and traps exits : channel killed", %{
      supervisor: supervisor
    } do
      zelf = self()

      caller_pid =
        spawn(fn ->
          assert {:ok, chan} = Coelho.Supervisor.get_managed_channel(supervisor)
          send(zelf, {:chan, chan})

          receive do
            :die -> :ok
          end
        end)

      assert Process.alive?(caller_pid)
      assert_receive {:chan, chan}

      Process.exit(chan.pid, :kill)

      refute Process.alive?(chan.pid)
      assert Process.alive?(caller_pid)
    end

    test "links the channel to the caller process and traps exits : caller killed", %{
      supervisor: supervisor
    } do
      zelf = self()

      caller_pid =
        spawn(fn ->
          assert {:ok, chan} = Coelho.Supervisor.get_managed_channel(supervisor)
          send(zelf, {:chan, chan})

          receive do
            :die -> :ok
          end
        end)

      assert Process.alive?(caller_pid)
      assert_receive {:chan, chan}, 100

      Process.exit(caller_pid, :kill)

      refute Process.alive?(chan.pid)
      refute Process.alive?(caller_pid)
    end
  end
end
