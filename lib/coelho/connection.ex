defmodule Coelho.Connection do
  use GenServer

  require Logger

  @reconnect_interval_ms 5000

  def init(_opts) do
    send self(), :connect
    Logger.info("Starting connection manager")

    {:ok, %{}}
  end

  def start_link() do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def handle_call(:get_connection, _from, state) do
    Logger.debug("Getting connection")

    case Map.fetch(state, :conn) do
      {:ok, conn } -> {:reply, {:ok, conn}, state}
      :error -> {:reply, {:error, :no_connection}, %{}}
    end
  end

  def handle_info(:connect, state) do
    Logger.info("Trying to connect to broker...")

    if is_pid(state[:conn]) do
      {:noreply, state}
    else
      case connect() do
        {:ok, conn} ->
          state = Map.put(state, :conn, conn)
          {:noreply, state}
        _error ->
          :erlang.send_after(@reconnect_interval_ms, self(), :connect)
          {:noreply, state}
      end
    end
  end

  def handle_info({:DOWN, _, :process, _pid, reason}, _) do
    Logger.error("Disconnected from broker: #{inspect(reason)}")

    send self(), :connect

    {:noreply, %{}}
  end

  def connect() do
    config = Application.get_env(:coelho, Coelho.Connection)

    case AMQP.Connection.open(config) do
      {:ok, conn} ->
        Process.monitor(conn.pid)
        Logger.info("Connected to rabbitmq: #{inspect(conn)}")
        {:ok, conn}

      {:error, reason} ->
        Logger.error("Cannot connect: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def get do
    GenServer.call(__MODULE__, :get_connection)
  end

end
