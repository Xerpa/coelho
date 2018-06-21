defmodule Coelho.Connection do
  use GenServer

  require Logger

  @reconnect_interval_ms 5000

  def init(_opts) do
    connect()
  end

  def start_link() do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def connect() do
    config = Application.get_env(:coelho, Coelho.Connection)

    case AMQP.Connection.open(config) do
      {:ok, conn} ->
        Logger.info("Connected to rabbitmq")
        Process.monitor(conn.pid)
        {:ok, %{conn: conn}}

      {:error, _} ->
        Logger.error("Cannot connect to rabbitmq. Waiting #{@reconnect_interval_ms} ms.")
        :timer.sleep(@reconnect_interval_ms)
        connect()
    end
  end

  def handle_info({:DOWN, _, :process, _pid, reason}, _) do
    Logger.error("Disconnected from broker: #{reason}")
    {:ok, conn} = connect()
    {:noreply, %{conn: conn}}
  end

  def handle_call(:get_connection, _from, state = %{conn: conn}) do
    {:reply, conn, state}
  end

  def get do
    GenServer.call(__MODULE__, :get_connection)
  end
end
