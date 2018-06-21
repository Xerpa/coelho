defmodule Coelho do
  alias Coelho.Connection

  require Logger

  def enqueue(exchange, routing_key, message, opts) do
    opts = Keyword.merge(opts, persistent: true, mandatory: true)

    with_channel(fn chan ->
      AMQP.Basic.publish(
        chan,
        exchange,
        routing_key,
        message,
        opts
      )
    end)
  end

  def with_channel(fun) do
    conn = Connection.get()

    with {:ok, chan} <- AMQP.Channel.open(conn) do
      try do
        AMQP.Confirm.select(chan)
        fun.(chan)
        AMQP.Confirm.wait_for_confirms_or_die(chan, 10_000)
      catch
        _kind, cause ->
          Logger.error("Error sending message to rabbitmq... #{inspect(cause)} ")
          :error
      end
    end
  end
end
