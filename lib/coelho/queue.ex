defmodule Coelho.Queue do
  def bind(channel, queue, exchange, options \\ []) do
    AMQP.Queue.bind(channel, queue, exchange, options)
  end

  def declare(channel, queue \\ "", options \\ []) do
    AMQP.Queue.declare(channel, queue, options)
  end

  def delete(channel, queue, options \\ []) do
    AMQP.Queue.delete(channel, queue, options)
  end

  def unbind(channel, queue, exchange, options \\ []) do
    AMQP.Queue.unbind(channel, queue, exchange, options)
  end

  def status(channel, queue) do
    AMQP.Queue.status(channel, queue)
  end
end
