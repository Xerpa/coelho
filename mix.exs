defmodule Coelho.MixProject do
  use Mix.Project

  def project do
    [
      app: :coelho,
      version: "0.0.1",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Coelho.Application, []}
    ]
  end

  defp deps do
    [
      {:amqp, "~> 2.1"}
    ]
  end
end
