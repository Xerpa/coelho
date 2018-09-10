defmodule Coelho.Confirm do
  alias AMQP.Confirm

  def select(channel) do
    Confirm.select(channel)
  end

  def wait_for_confirms(channel) do
    Confirm.wait_for_confirms(channel)
  end

  def wait_for_confirms(channel, timeout) do
    Confirm.wait_for_confirms(channel, timeout)
  end

  def wait_for_confirms_or_die(channel) do
    Confirm.wait_for_confirms_or_die(channel)
  end

  def wait_for_confirms_or_die(channel, timeout) do
    Confirm.wait_for_confirms_or_die(channel, timeout)
  end
end
