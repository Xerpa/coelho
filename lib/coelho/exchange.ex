defmodule Coelho.Exchange do
  def declare(channel, exchange, type \\ :direct, options \\ []) do
    AMQP.Exchange.declare(channel, exchange, type, options)
  end
end
