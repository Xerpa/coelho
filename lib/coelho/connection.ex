defmodule Coelho.Connection do
  use GenServer

  require Logger

  @reconnect_interval_ms 5000

  def init(_opts) do
    {:ok, new_state(), 0}
  end

  def start_link() do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def connect(state) do
    config = Application.get_env(:coelho, Coelho.Connection)

    case AMQP.Connection.open(config) do
      {:ok, conn} ->
        Logger.debug("Connected to rabbitmq: #{inspect(conn)}")
        conn_ref = Process.monitor(conn.pid)

        state
        |> Map.put(:conn, conn)
        |> Map.put(:conn_ref, conn_ref)

      {:error, _} ->
        :timer.sleep(@reconnect_interval_ms)
        connect()
    end
  end

  def handle_call(:get_connection, _from, %{conn: conn} = state), do: {:reply, conn, state}

  def handle_call(:get_connection, _from, state) do
    Logger.debug("Getting connection")

    state = connect(state)

    {:reply, conn, state}
  end

  def handle_call(:open_channel, _from, %{conn: conn} = state) do
    Logger.debug("Openning channel")

    result = AMQP.Channel.open(conn)

    {:reply, result, state}
  end

  def handle_call(:open_channel, from, state) do
    Logger.debug("Getting connection")

    state = connect(state)

    handle_call(:open_channel, from, state)
  end

  def handle_call({:open_managed_channel, on_open_fn}, from, %{conn: conn} = state) when is_function(on_open_fn, 1) do
    case Map.fetch(state.channels, from) do
      {:ok, chan} ->
        {:reply, {:ok, chan}, state}

      :error ->
        {state, chan} = open_managed_channel_impl(state, from, on_open_fn)

        {:reply, {:ok, chan}, state}
    end
  end

  def handle_call({:open_managed_channel, on_open_fn}, from, state) when is_function(on_open_fn, 1) do
    Logger.debug("Getting connection")

    state = connect(state)

    handle_call({:open_managed_channel, on_open_fn}, from state)
  end

  def handle_call(:get_managed_channel, from, state) do
    case Map.fetch(state.channels, from) do
      {:ok, chan} ->
        {:reply, {:ok, chan}, state}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_info({:DOWN, conn_ref, :process, _pid, reason}, state = %{conn_ref: conn_ref}) do
    Logger.error("Disconnected from broker: #{inspect(reason)}")

    {:noreply, new_state()}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    cond do
      Map.get(state.consumer_references, ref) ->
        handle_consumer_down(state, ref)

      Map.get(state.channel_references, ref) ->
        handle_channel_down(state, ref)
    end
  end

  defp handle_consumer_down(state, consumer_ref) do
    %{consumer_pid: consumer_pid, channel_reference: channel_ref} = Map.fetch!(state.consumer_references, consumer_ref)

    with {:ok, chan} <- Map.fetch(state.managed_channels, consumer_pid) do
      AMQP.Channel.close(chan)
    end

    state =
      state
      |> Map.update!(:consumer_references, & Map.delete(&1, consumer_ref))
      |> Map.update!(:managed_channels, & Map.delete(&1, consumer_pid))
      |> Map.update!(:channel_references, & Map.delete(&1, channel_ref))

    {:noreply, state}
  end

  defp handle_channel_down(state, channel_ref) do
    %{on_open_fn: on_open_fn, consumer_pid: consumer_pid} = Map.fetch!(state.channel_references, channel_ref)

    {state, chan} = open_managed_channel_impl(state, consumer_pid, on_open_fn)

    state = Map.update!(state, :managed_channels, & Map.put(&1, :consumer_pid, chan))

    {:noreply, state}
  end

  def handle_info(:timeout, state) do
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

  def open_channel() do
    GenServer.call(__MODULE__, :open_channel)
  end

  def open_managed_channel() do
    GenServer.call(__MODULE__, :open_managed_channel)
  end

  def get_managed_channel() do
    GenServer.call(__MODULE__, :get_managed_channel)
  end

  defp new_state() do
    %{managed_channels: %{}, consumer_references: %{}, channel_references: %{}}
  end

  defp open_managed_channel_impl(state, from, on_open_fn) do
    conn = state.conn

    Logger.debug("Openning managed channel")

    {:ok, chan} = AMQP.Channel.open(conn)

    chan_ref = Process.monitor(chan.pid)

    consumer_ref = Process.monitor(from)

    state =
      state
      |> Map.update!(:consumer_references, & Map.put(&1, consumer_ref, %{consumer_pid: from, channel_reference: chan_ref}))
      |> Map.update!(:managed_channels, & Map.put(&1, from, chan))
      |> Map.update!(:channel_references, & Map.put(&1, chan_ref, %{on_open_fn: on_open_fn, consumer_pid: from}))

    on_open_fn.(chan)

    {chan, state}
  end
end
