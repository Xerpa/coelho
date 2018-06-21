defmodule CoelhoTest do
  use ExUnit.Case
  doctest Coelho

  test "greets the world" do
    assert Coelho.hello() == :world
  end
end
