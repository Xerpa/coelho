defmodule Coelho.Supervisor do
  use GenServer

  alias Coelho.Channel
  alias Coelho.Connection

  require Logger

  @reconnect_interval_ms 5000

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
    key = {__MODULE__, :channel}

    case Process.get(key) do
      nil ->
        open_managed_channel(pid, key)

      chan = %AMQP.Channel{} ->
        if Process.alive?(chan.pid) do
          {:ok, chan}
        else
          open_managed_channel(pid, key)
        end
    end
  end

  defp open_managed_channel(pid, key) do
    with {:ok, chan} <- new_channel(pid) do
      Process.flag(:trap_exit, true)
      Process.link(chan.pid)
      Process.put(key, chan)

      {:ok, chan}
    end
  end

  defp new_state() do
    %{managed_channels: %{}, consumer_references: %{}, channel_references: %{}}
  end
end
