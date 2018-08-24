defmodule Coelho do
  alias Coelho.Channel
  alias Coelho.Basic

  require Logger

  def enqueue(exchange, routing_key, message, opts \\ []) do
    opts = Keyword.merge(opts, persistent: true, mandatory: true)

    with_channel(fn chan ->
      Basic.publish(
        chan,
        exchange,
        routing_key,
        message,
        opts
      )
    end)
  end

  def with_channel(fun, pid \\ Coelho.Supervisor) when is_function(fun, 1) do
    Coelho.Supervisor.with_channel(pid, fun)
  end

  def open_managed_channel(pid \\ Coelho.Supervisor, on_start_fn)
      when is_function(on_start_fn, 1) do
    Coelho.Supervisor.open_managed_channel(pid, on_start_fn)
  end

  def get_managed_channel(pid \\ Coelho.Supervisor) do
    Coelho.Supervisor.get_managed_channel(pid)
  end
end
