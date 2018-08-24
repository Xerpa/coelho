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

  describe "with_channel" do
    test "executes function and closes channel", %{supervisor: supervisor} do
      test_pid = self()

      result =
        Coelho.Supervisor.with_channel(supervisor, fn chan ->
          send(test_pid, {:chan, chan})
          :done
        end)

      assert :done == result
      assert_receive {:chan, %AMQP.Channel{pid: chan_pid}}
      assert is_pid(chan_pid)
      :timer.sleep(100)
      refute Process.alive?(chan_pid)
    end
  end

  describe "connection" do
    test "should reconnect to rabbitmq", %{supervisor: supervisor} do
      {:ok, conn} = Coelho.Supervisor.get_connection(supervisor)

      Process.exit(conn.pid, :kill)

      {:ok, new_conn} = Coelho.Supervisor.get_connection(supervisor)

      refute Process.alive?(conn.pid)
      assert Process.alive?(new_conn.pid)
    end
  end

  describe "managed channel" do
    test "opens a new managed channel", %{supervisor: supervisor} do
      zelf = self()

      on_start_fn = fn chan ->
        send(zelf, :on_start_fn_called)
        assert %AMQP.Channel{} = chan
        :init_fn_result
      end

      assert {:ok, %AMQP.Channel{} = chan, :init_fn_result} =
               Coelho.Supervisor.open_managed_channel(supervisor, on_start_fn)

      assert_receive :on_start_fn_called
    end

    test "returns the same channel if already open", %{supervisor: supervisor} do
      zelf = self()

      on_start_fn = fn chan ->
        send(zelf, :on_start_fn_called)
        assert %AMQP.Channel{} = chan
        :init_fn_result
      end

      assert {:ok, chan0, :init_fn_result} =
               Coelho.Supervisor.open_managed_channel(supervisor, on_start_fn)

      assert {:ok, chan1} = Coelho.Supervisor.get_managed_channel(supervisor)
      assert {:ok, chan2} = Coelho.Supervisor.get_managed_channel(supervisor)

      assert chan0.pid == chan1.pid
      assert chan1.pid == chan2.pid

      assert_receive :on_start_fn_called
      refute_receive :on_start_fn_called
    end

    test "links the channel to the caller process : channel killed", %{
      supervisor: supervisor
    } do
      zelf = self()

      caller_pid =
        spawn(fn ->
          assert {:ok, chan, :res} =
                   Coelho.Supervisor.open_managed_channel(supervisor, fn _ -> :res end)

          send(zelf, {:chan, chan})

          receive do
            :die -> :ok
          end
        end)

      assert Process.alive?(caller_pid)
      assert_receive {:chan, chan}

      Process.exit(chan.pid, :kill)

      refute Process.alive?(chan.pid)
      refute Process.alive?(caller_pid)
    end

    test "cleans up the cannel after caller is down", %{
      supervisor: supervisor
    } do
      zelf = self()

      caller_pid =
        spawn(fn ->
          assert {:ok, chan, res} =
                   Coelho.Supervisor.open_managed_channel(supervisor, fn _ -> :res end)

          send(zelf, {:chan, chan})

          receive do
            :die -> :ok
          end
        end)

      assert Process.alive?(caller_pid)
      assert_receive {:chan, chan}, 100

      send(caller_pid, :die)

      channel_ref = Process.monitor(chan.pid)

      assert_receive {:DOWN, ^channel_ref, _, _, _}
      refute Process.alive?(chan.pid)
      refute Process.alive?(caller_pid)
    end
  end
end
