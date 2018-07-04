defmodule Coelho.Channel do
  def close(channel) do
    AMQP.Channel.close(channel)
  end
end
