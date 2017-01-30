# TaskBunny

**TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

  1. Add `task_bunny` to your list of dependencies in `mix.exs`:

        def deps do
          [{:task_bunny, "~> 0.1.0"}]
        end

  1. Ensure `task_bunny` is started before your application:

        def application do
          [applications: [:task_bunny]]
        end

  1. Configure hosts and jobs

```elixir
config :task_bunny, hosts: [
  default: [
    # See more options on
    # https://github.com/pma/amqp/blob/master/lib/amqp/connection.ex
    connect_options: "amqp://localhost"
  ]
]

config :task_bunny, jobs: [
  [job: YourApp.HelloJob, concurrency: 5],
  [job: YourApp.HolaJob, concurrency: 2]
]
```

When you use TaskBunny under an umbrella app and each apps needs different job
definition, you can prefix jobs like below.

```elixir
config :task_bunny, app_a_jobs: [
  [job: AppA.HelloJob, concurrency: 5]
]

config :task_bunny, app_b_jobs: [
  [job: AppB.HolaJob, concurrency: 5]
]

```

## How To Use

### Defining a Job module

```elixir
defmodule HeavyProcessing do
  use TaskBunny.Job

  def perform(%{"id" => id}) do
    # what you need to do
  end
end
```

### Enqueueing the job

```elixir
TaskBunny.SyncPublisher.push HeavyProcessing, %{"id" => 123123}
```
