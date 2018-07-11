defmodule Coelho.Supervisor do
  use GenServer

  alias Coelho.Channel
  alias Coelho.Connection

  require Logger

  @reconnect_interval_ms 5000
  @channel_key {__MODULE__, :channel}

  def start_link(opts \\ [name: __MODULE__]) do
    if opts[:name] do
      GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
    else
      GenServer.start_link(__MODULE__, %{})
    end
  end

  def init(_opts) do
    Logger.info("Starting Coelho Supervisor")

    Process.flag(:trap_exit, true)

    {:ok, new_state(), 0}
  end

  def connect(state) do
    config = Application.get_env(:coelho, Coelho.Connection)

    with {:ok, conn} <- Connection.open(config) do
      Logger.debug("Connected to rabbitmq: #{inspect(conn)}")
      conn_ref = Process.monitor(conn.pid)

      state =
        state
        |> Map.put(:conn, conn)
        |> Map.put(:conn_ref, conn_ref)

      {:ok, state}
    end
  end

  def terminate(_reason, state) do
    with {:ok, conn} <- Map.fetch(state, :conn) do
      Connection.close(conn)
    end

    :ok
  end

  def handle_call(:get_connection, _from, state) do
    Logger.debug("Getting connection")

    with {:ok, conn} <- Map.fetch(state, :conn),
         true <- Process.alive?(conn.pid) do
      {:reply, {:ok, conn}, state}
    else
      _ ->
        case connect(state) do
          {:ok, state} ->
            {:reply, {:ok, state.conn}, state}

          error ->
            {:reply, error, state}
        end
    end
  end

  def handle_call(:new_channel, from, state) do
    case Map.fetch(state, :conn) do
      {:ok, conn} ->
        res = Channel.open(conn)
        {:reply, res, state}

      :error ->
        with {:ok, state} <- connect(state) do
          res = Chanell.open(state.conn)
          {:reply, res, state}
        else
          error ->
            {:reply, error, state}
        end
    end
  end

  def handle_info({:DOWN, conn_ref, :process, _pid, reason}, state = %{conn_ref: conn_ref}) do
    Logger.error("Disconnected from broker: #{inspect(reason)}")

    Process.send_after(self(), :timeout, 0)

    {:noreply, new_state()}
  end

  def handle_info(msg = {:DOWN, _, :process, _pid, _}, state) do
    Logger.debug("Ignoring DOWN message: #{inspect(msg)}")

    {:noreply, state}
  end

  def handle_info(:timeout, state) do
    if is_pid(state[:conn]) do
      {:noreply, state}
    else
      case connect(state) do
        {:ok, state} ->
          {:noreply, state}

        _error ->
          :erlang.send_after(@reconnect_interval_ms, self(), :timeout)
          {:noreply, state}
      end
    end
  end

  def get_connection(pid \\ __MODULE__) do
    GenServer.call(pid, :get_connection)
  end

  def new_channel(pid \\ __MODULE__) do
    GenServer.call(pid, :new_channel)
  end

  def get_managed_channel(pid \\ __MODULE__) do
    case Process.get(@channel_key) do
      nil ->
        {:error, :channel_not_opened}

      %{channel: chan, on_start_fn: on_start_fn} ->
        if Process.alive?(chan.pid) do
          {:ok, chan}
        else
          open_managed_channel_impl(pid, on_start_fn)
        end
    end
  end

  def open_managed_channel(pid \\ __MODULE__, on_start_fn) when is_function(on_start_fn, 1) do
    case Process.get(@channel_key) do
      nil ->
        open_managed_channel_impl(pid, on_start_fn)

      %{channel: chan = %AMQP.Channel{}} ->
        if Process.alive?(chan.pid) do
          {:ok, chan}
        else
          open_managed_channel_impl(pid, on_start_fn)
        end
    end
  end

  defp open_managed_channel_impl(pid, on_start_fn) do
    with {:ok, chan} <- new_channel(pid) do
      spawn_watcher(chan)
      Process.put(@channel_key, %{channel: chan, on_start_fn: on_start_fn})
      on_start_fn.(chan)

      {:ok, chan}
    end
  end

  defp spawn_watcher(channel) do
    caller = self()

    spawn(fn ->
      tag = Process.monitor(caller)

      receive do
        {:DOWN, ^tag, _, _, _} ->
          Channel.close(channel)
          :ok
      end
    end)
  end

  defp new_state() do
    %{managed_channels: %{}, consumer_references: %{}, channel_references: %{}}
  end
end
