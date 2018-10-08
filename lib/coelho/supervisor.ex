defmodule Coelho.Supervisor do
  use GenServer

  alias Coelho.Channel
  alias Coelho.Connection

  require Logger

  @reconnect_interval_ms 5000
  @channel_key {__MODULE__, :channel}
  @on_init_res_key {__MODULE__, :on_init_res}

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

  def handle_call({:with_channel, fun}, from, state) do
    with {:ok, conn} <- Map.fetch(state, :conn),
         true <- Process.alive?(conn.pid),
         {:ok, chan} <- Channel.open(conn) do
      result =
        try do
          AMQP.Confirm.select(chan)
          result = fun.(chan)
          AMQP.Confirm.wait_for_confirms_or_die(chan, 10_000)
          result
        rescue
          e ->
            Logger.error("Error sending message to rabbitmq... #{inspect(e)} ")
            :error
        catch
          _kind, cause ->
            Logger.error("Error sending message to rabbitmq... #{inspect(cause)} ")
            :error
        after
          Logger.debug("Closing channel")
          AMQP.Channel.close(chan)
        end

      GenServer.reply(from, result)
    end

    {:noreply, state}
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

  def handle_call(:new_channel, _from, state) do
    case Map.fetch(state, :conn) do
      {:ok, conn} ->
        res = Channel.open(conn)
        {:reply, res, state}

      :error ->
        with {:ok, state} <- connect(state) do
          res = Channel.open(state.conn)
          {:reply, res, state}
        else
          error ->
            {:reply, error, state}
        end
    end
  end

  def handle_info({:DOWN, conn_ref, :process, _pid, reason}, %{conn_ref: conn_ref}) do
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

  def with_channel(pid \\ __MODULE__, fun) when is_function(fun, 1) do
    GenServer.call(pid, {:with_channel, fun})
  end

  def new_channel(pid \\ __MODULE__) do
    GenServer.call(pid, :new_channel)
  end

  @doc """
  Gets the managed channel after it has already been opened. If the
  channel PID has died since the last call to `get_managed_channel/0`,
  it will be reopened and the `on_start_fn/1` callback will be invoked
  again before returning the channel.

  Note that `open_managed_channel/1` **must** be called before this
  function. Calling `get_managed_channel/0` without
  `open_managed_channel/1` will return `{:error,
  :channel_not_opened}`.
  """
  def get_managed_channel(pid \\ __MODULE__) do
    case Process.get(@channel_key) do
      nil ->
        {:error, :channel_not_opened}

      %{channel: chan, on_start_fn: on_start_fn} ->
        if Process.alive?(chan.pid) do
          res = Process.get(@on_init_res_key)
          {:ok, chan}
        else
          open_managed_channel_impl(pid, on_start_fn, false)
        end
    end
  end

  @doc """
  Opens a channel associated with the calling PID that is managed by
  Coelho.

  The calling PID (_the owner_) should not store nor managed such
  channel. In the event the channel PID dies, it will be recreated the
  next time the owner tries to use `get_managed_channel/0`. The owner
  **must** be prepared to handle exit signals from the channel PID in
  the event it dies, or trap such messages using
  `Process.flag(:trap_exit, true)`.

  A start callback `on_start_fn/1` must be supplied in order to do
  initial setup such as consuming from a queue or setting up the
  channel QOS options. That function will receive the channel as an
  argument. Note that this start callback will possibly be invoked
  multiple times, once for each channel creation.

  When the owner terminates, the channel is automatically closed.
  """
  def open_managed_channel(pid \\ __MODULE__, on_start_fn) when is_function(on_start_fn, 1) do
    case Process.get(@channel_key) do
      nil ->
        open_managed_channel_impl(pid, on_start_fn, true)

      %{channel: chan = %AMQP.Channel{}} ->
        if Process.alive?(chan.pid) do
          res = Process.get(@on_init_res_key)
          {:ok, chan, res}
        else
          open_managed_channel_impl(pid, on_start_fn, true)
        end
    end
  end

  defp open_managed_channel_impl(pid, on_start_fn, return_on_init_res?) do
    with {:ok, chan} <- new_channel(pid) do
      spawn_watcher(chan)
      Process.put(@channel_key, %{channel: chan, on_start_fn: on_start_fn})
      res = on_start_fn.(chan)
      Process.link(chan.pid)
      Process.put(@on_init_res_key, res)

      if return_on_init_res? do
        {:ok, chan, res}
      else
        {:ok, chan}
      end
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
