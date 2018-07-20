defmodule Coelho do
  alias Coelho.Channel
  alias Coelho.Basic

  require Logger

  def enqueue(exchange, routing_key, message, opts \\ []) do
    opts = Keyword.merge(opts, persistent: true, mandatory: true)

    with_channel(fn chan ->
      Basic.publish(
        chan,
        exchange,
        routing_key,
        message,
        opts
      )
    end)
  end

  def with_channel(fun, pid \\ Coelho.Supervisor) do
    with {:ok, conn} <- Coelho.Supervisor.get_connection(pid),
         {:ok, chan} <- Channel.open(conn) do
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
    end
  end

  def open_managed_channel(pid \\ Coelho.Supervisor, on_start_fn)
      when is_function(on_start_fn, 1) do
    Coelho.Supervisor.open_managed_channel(pid, on_start_fn)
  end

  def get_managed_channel(pid \\ Coelho.Supervisor) do
    Coelho.Supervisor.get_managed_channel(pid)
  end
end
