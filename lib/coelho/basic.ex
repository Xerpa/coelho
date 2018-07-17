defmodule Coelho.Basic do
  def ack(channel, delivery_tag, options \\ []) do
    AMQP.Basic.ack(channel, delivery_tag, options)
  end

  def nack(channel, delivery_tag, options \\ []) do
    AMQP.Basic.nack(channel, delivery_tag, options)
  end

  def consume(chan, queue, consumer_pid \\ nil, options \\ []) do
    try do
      AMQP.Basic.consume(chan, queue, consumer_pid, options)
    catch
      _k, e -> {:error, e}
    end
  end

  def get(chan, queue, options \\ []) do
    AMQP.Basic.get(chan, queue, options)
  end

  def publish(channel, exchange, routing_key, payload, options \\ []) do
    AMQP.Basic.publish(channel, exchange, routing_key, payload, options)
  end

  def qos(chan, opts \\ []) do
    AMQP.Basic.qos(chan, opts)
  end

  def reject(channel, delivery_tag, options \\ []) do
    AMQP.Basic.reject(channel, delivery_tag, options)
  end

  def cancel(channel, consumer_tag, options \\ []) do
    AMQP.Basic.cancel(channel, consumer_tag, options)
  end
end
