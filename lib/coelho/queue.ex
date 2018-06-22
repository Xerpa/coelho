defmodule Coelho.Queue do
  def bind(channel, queue, exchange, options \\ []) do
    AMQP.Queue.bind(channel, queue, exchange, options)
  end

  def declare(channel, queue \\ "", options \\ []) do
    AMQP.Queue.declare(channel, queue, options)
  end
end
