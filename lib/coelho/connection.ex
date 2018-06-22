defmodule Coelho.Connection do
  use GenServer

  require Logger

  @reconnect_interval_ms 5000

  def init(_opts) do
    {:ok, %{}}
  end

  def start_link() do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def connect() do
    config = Application.get_env(:coelho, Coelho.Connection)

    case AMQP.Connection.open(config) do
      {:ok, conn} ->
        Logger.info("Connected to rabbitmq: #{inspect(conn)}")
        Process.monitor(conn.pid)
        {:ok, conn}

      {:error, _} ->
        Logger.error("Cannot connect to rabbitmq. Waiting #{@reconnect_interval_ms} ms.")
        :timer.sleep(@reconnect_interval_ms)
        connect()
    end
  end

  def handle_info({:DOWN, _, :process, pid, reason}, _) do
    Logger.error("Disconnected from broker: #{reason}")

    {:noreply, %{}}
  end

  def handle_call(:get_connection, _from, %{conn: conn} = state), do: {:reply, conn, state}

  def handle_call(:get_connection, _from, state) do
    Logger.info("Getting connection")

    {:ok, conn} = connect()

    {:reply, conn, %{conn: conn}}
  end

  def handle_call(:open_channel, _from, %{conn: conn} = state) do
    Logger.info("Openning channel")

    result = AMQP.Channel.open(conn)

    {:reply, result, state}
  end

  def get do
    GenServer.call(__MODULE__, :get_connection)
  end

  def open_channel() do
    GenServer.call(__MODULE__, :open_channel)
  end
end
