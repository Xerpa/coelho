use Mix.Config

config :coelho, Coelho.Connection,
  heartbet: 30,
  host: "localhost",
  port: (System.get_env("coelho_port") || "5672") |> String.to_integer(),
  virtual_host: "/",
  username: "guest",
  password: "guest"

# Stop lager redirecting :error_logger messages
config :lager, :error_logger_redirect, false

# Stop lager removing Logger's :error_logger handler
config :lager, :error_logger_whitelist, [Logger.ErrorHandler]
