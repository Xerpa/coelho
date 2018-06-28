defmodule Coelho.Exchange do
  def declare(channel, exchange, type \\ :direct, options \\ []) do
    AMQP.Exchange.declare(channel, exchange, type, options)
  end

  def delete(channel, exchange, options \\ []) do
    AMQP.Exchange.delete(channel, exchange, options)
  end
end
