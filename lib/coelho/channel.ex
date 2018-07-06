defmodule Coelho.Channel do
  alias Coelho.Connection

  require Logger

  def close(channel) do
    AMQP.Channel.close(channel)
  end

  def open(conn) do
    AMQP.Channel.open(conn)
  end
end
