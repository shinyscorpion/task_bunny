defmodule TaskBunny.Mixfile do
  use Mix.Project
  @version "0.0.1-dev.3"

  def project do
    [
      app: :task_bunny,
      version: @version,
      elixir: "~> 1.4",
      elixirc_paths: elixirc_paths(Mix.env),
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      deps: deps(),
      # Docs
      name: "TaskBunny",
      source_url: "https://github.com/shinyscorpion/task_bunny",
      docs:
        [
          extras:
            [
              "README.md",
            ],
        ],
      description: description(),
      package: package(),
      xref: [exclude: [Wobserver]],
    ]
  end

  defp description do
    """
    Background processing application/library written in Elixir that uses RabbitMQ as a messaging backend
    """
  end

  defp package do
    [
      name: :task_bunny,
      files: ["lib","mix.exs","README.md","LICENSE.md"],
      maintainers: ["Ian Luites", "Tatsuya Ono", "Ricardo Perez", "Francesco Grammatico"],
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
      {:poison, "~> 2.0"},
      {:amqp, "~> 0.2.0-pre.1"},
      {:meck, "~> 0.8.2", only: :test},
      {:logger_file_backend, "~> 0.0.9", only: :test},
      {:ex_doc, "~> 0.14", only: :dev},
    ]
  end
end
