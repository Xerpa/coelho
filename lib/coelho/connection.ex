defmodule Coelho.Connection do
  def open(options \\ []) do
    AMQP.Connection.open(options)
  end

  def close(conn) do
    AMQP.Connection.close(conn)
  end
end
