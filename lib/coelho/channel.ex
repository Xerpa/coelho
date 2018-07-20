defmodule Coelho.Channel do
  def close(channel) do
    AMQP.Channel.close(channel)
  end

  def open(conn) do
    AMQP.Channel.open(conn)
  end
end
