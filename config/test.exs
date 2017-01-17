use Mix.Config

config :logger, backends: [{LoggerFileBackend, :log_file}]
config :logger, :log_file, level: :debug, path: "logs/test.log"
