defmodule Coelho do
  alias Coelho.Connection

  require Logger

  def enqueue(exchange, routing_key, message, opts) do
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

  def with_channel(fun) do
    with {:ok, chan} <- Connection.open_channel() do
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
        Logger.info("Closing channel")
        AMQP.Channel.close(chan)
      end
    end
  end
end
