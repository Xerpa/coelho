defmodule Coelho.Channel do

  alias Coelho.Connection

  require Logger

  def close(channel) do
    AMQP.Channel.close(channel)
  end

  def open() do
    Logger.debug("Openning channel..")
    case Connection.get() do
      {:ok, conn} -> AMQP.Channel.open(conn)
      {:error, _ } -> {:error, :no_connection}
    end
  end

end
