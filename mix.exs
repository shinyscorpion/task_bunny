defmodule TaskBunny.Mixfile do
  use Mix.Project

  @version "0.3.3"
  @description "Background processing application/library written in Elixir that uses RabbitMQ as a messaging backend"

  def project do
    [
      app: :task_bunny,
      version: @version,
      elixir: "~> 1.7",
      elixirc_paths: elixirc_paths(Mix.env()),
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "TaskBunny",
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],
      dialyzer: [ignore_warnings: "dialyzer.ignore-warnings"],
      docs: [
        extras: ["README.md"],
        main: "readme",
        source_ref: "v#{@version}",
        source_url: "https://github.com/shinyscorpion/task_bunny"
      ],
      description: @description,
      package: package(),
      xref: [exclude: [Wobserver]]
    ]
  end

  defp package do
    [
      name: :task_bunny,
      files: [
        # Project files
        "mix.exs",
        "README.md",
        "LICENSE.md",
        # TaskBunny
        "lib/task_bunny.ex",
        "lib/task_bunny",
        # Tasks
        "lib/mix/tasks/task_bunny.queue.reset.ex"
      ],
      maintainers: [
        "Antonio Sagliocco",
        "Elliott Hilaire",
        "Francesco Grammatico",
        "Ian Luites",
        "Kenneth Lee",
        "Ricardo Perez",
        "Tatsuya Ono"
      ],
      licenses: ["MIT"],
      links: %{"Github" => "https://github.com/shinyscorpion/task_bunny"}
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {TaskBunny, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:amqp, "~> 0.3.1"},
      {:poison, "~> 2.0 or ~> 3.0"},

      # dev/test
      {:credo, "~> 0.6", only: [:dev]},
      {:dialyxir, "~> 0.4", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.14", only: :dev},
      {:excoveralls, "~> 0.5", only: :test},
      {:inch_ex, "~> 0.5", only: [:dev, :test]},
      {:logger_file_backend, "~> 0.0.9", only: :test},
      {:meck, "~> 0.8.2", only: :test},
      {:poolboy, "~> 1.5"}
    ]
  end
end
