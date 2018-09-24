defmodule CoelhoTest do
  use ExUnit.Case
  doctest Coelho

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
        Coelho.with_channel(
          fn chan ->
            send(test_pid, {:chan, chan})
            :done
          end,
          supervisor
        )

      assert :done == result
      assert_receive {:chan, %AMQP.Channel{pid: chan_pid}}
      assert is_pid(chan_pid)
      :timer.sleep(50)
      refute Process.alive?(chan_pid)
    end
  end
end
