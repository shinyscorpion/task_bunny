# TaskBunny

[![Hex.pm](https://img.shields.io/hexpm/v/task_bunny.svg "Hex")](https://hex.pm/packages/task_bunny)
[![Build Status](https://travis-ci.org/shinyscorpion/task_bunny.svg?branch=master)](https://travis-ci.org/shinyscorpion/task_bunny)
[![Inline docs](http://inch-ci.org/github/shinyscorpion/task_bunny.svg?branch=master)](http://inch-ci.org/github/shinyscorpion/task_bunny)
[![Deps Status](https://beta.hexfaktor.org/badge/all/github/shinyscorpion/task_bunny.svg)](https://beta.hexfaktor.org/github/shinyscorpion/task_bunny)
[![Hex.pm](https://img.shields.io/hexpm/l/task_bunny.svg "License")](LICENSE.md)

TaskBunny is a background processing application written in Elixir and uses RabbitMQ as a messaging backend.

## Why RabbitMQ? Why not Erlang process?

A fair question and we are not surprised by that.
OTP allows you run background processes concurrently in a distributed manner.
Why do we need RabbitMQ for background processing?

Well, first of all, if you don't need to persist messages(job requests) outside your system, we suggest you use an Erlang process.
Erlang process and OTP would always be your first choice for background processing in Elixir.

TaskBunny might be of interest if you:

- have reasons to persist and deliver messages outside your Elixir application
- consider using RabbitMQ as background processing message bus

Here are some of our reasons:

- We use Docker based deployment and each deploy is immutable and disposable.
- New to Elixir/Erlang so we don't want to change our infrastructure drastically yet.
- Need some background processes that access to internal/external systems around the world. We want to control concurrency and retry interval and see failed processes.

## Project status and versioning

TaskBunny is pre 0.1.
Please be aware that we plan to make breaking changes aggressively without considering backward compatibility.
We are still discussing core design decisions, like module structure.

We decided to open source this library because:

- It is used in our production code.
- We noticed people wanted to use RabbitMQ for the same purpose in their Elixir application.
- We want to hear from the community to make this library better.
- There are few examples and we have been helped by those examples. Inspired by that, we want to share our work before spending time on polishing.

Hopefully we can make 0.1 release soon but there is nothing preventing you trying out this library.

## Getting started

### Requirements

- Elixir 1.4
- RabbitMQ 3.6.0 or greater

TaskBunny heavily relies on [amqp](https://github.com/pma/amqp) by Paulo Almeida.

### Installation

1. Edit `mix.exs` and add `task_bunny` to your list of dependencies and applications:
  ```elixir
    def deps do
      [{:task_bunny, "~> 0.1.0-rc.1"}]
    end
    
    def application do
      [applications: [:task_bunny]]
    end
  ```
  
2. Configure hosts and queues
  ```elixir
    config :task_bunny, hosts: [
      default: [
        connect_options: "amqp://localhost?heartbeat=30" # Find more options on https://github.com/pma/amqp/blob/master/lib/amqp/connection.ex
      ]
    ]

    config :task_bunny, queue: [
      namespace: "task_bunny." # common prefix for queue name
      queues: [
        [name: "normal", jobs: :default],
        [name: "high", worker: [concurrency: 5], jobs: [EmergentJob, "Emergent.*"]]
      ]
    ]
  ```
  
### Define job module

Use `TaskBunny.Job` module in your job module and define `perform/1` that takes map as an argument.

```elixir
defmodule SampleJob do
  use TaskBunny.Job
  require Logger

  def perform(%{"id" => id}) do
    Logger.info("SampleJob was invoked with ID=#{id}")
  end
end
```

### Enqueueing job

Then enqueue a job

```elixir
:ok = SampleJob.enqueue(%{"id" => 123123})
```

The worker invokes the job with `SampleJob was invoked with ID=123123` in your logger output.

### Enqueueing job from other system

The message should be encoded in JSON format and set job and payload(argument).
For example:

```javascript
{
  "job": "YourApp.Jobs.SampleJob",
  "payload": {"id": 123}
}
```

Then send the message to the queue for the job.

## Design topics and features

### Queues

TaskBunny declares three queues for each worker queue on RabbitMQ.

```elixir
config :task_bunny, queue: [
  namespace: "task_bunny."
  queues: [
    [name: "normal", jobs: :default],
  ]
]
```

If have a config like above, TaskBunny will define those three queues:

- task_bunny.normal: main worker queue
- task_bunny.normal.retry: queue for retry
- task_bunny.normal.rejected: queue that stores jobs failed more than allowed times

### Concurrency

TaskBunny starts a process for a worker.
A worker listens to one queue and runs the number of jobs set in config file concurrently.

There is no limit on concurrency on TaskBunny layer.
You want to balance between performance and needs on throttle.

### Retry

TaskBunny retries the job if the job has failed.
By default, it retries 10 times for every 5 minutes.

If you want to change it, you can override the value on a job module.

```elixir
defmodule SampleJob do
  use TaskBunny.Job
  require Logger

  def perform(%{"id" => id}) do
    Logger.info("SampleJob was invoked with ID=#{id}")
  end

  def max_retry, do: 100
  def retry_interval(_), do: 10_000
end

```

In this example, it will retry 100 times for every 10 seconds.

If a job fails more than `max_retry` times, the payload is sent to `jobs.[job_name].rejected` queue.

Under the hood, TaskBunny uses [dead letter exchanges](https://www.rabbitmq.com/dlx.html) to support retry.

You can also change the retry_interval by the number of failures.

```elixir
  def max_retry, do: 5

  def retry_interval(failed_count) do
    # failed_count will be between 1 and 5.
    # Gradually have longer retry interval
    [10, 60, 300, 3_600, 7_200]
    |> Enum.map(&(&1 * 1000))
    |> Enum.at(failed_count - 1, 1000)
  end
```

### Timeout

By default, jobs timeout after 2 minutes.
If job doesn't respond for more than 2 minutes, worker kills the process and moves it to retry queue.

You can change the timeout by overriding `timeout/0` in your job.

```elixir
defmodule SlowJob do
  use TaskBunny.Job
  ...

  def timeout, do: 300_000
end

```

### Redefine queues

TaskBunny provides a mix task to reset queues.
This task deletes the queues and creates them again.
Existing messages in the queue will be lost so please be aware of this.

```
% mix task_bunny.queue.reset
```

You need to redefine a queue when you want to change the retry interval for a queue.


### Reconnection

TaskBunny automatically tries reconnecting to RabbitMQ if the connection is gone.
All workers will restart automatically once the new connection is established.

### Umbrella app

When you use TaskBunny under an umbrella app and each apps needs a different queue definition, you can prefix config key like below so that it doesn't ovewrwrite the other configuration.

```elixir
  config :task_bunny, app_a_queue: [
    [name: "normal", jobs: ["AppA.*"]]
  ]

  config :task_bunny, app_b_queue: [
    [name: "normal", jobs: ["AppB.*"]]
  ]
```

### Disable worker

When you don't want to run TaskBunny workers in an environment set `1`, `TRUE` or `YES` to `TASK_BUNNY_DISABLE_WORKER` environment variable.

### Wobserver Integration

TaskBunny automatically integrates with [Wobserver](https://github.com/shinyscorpion/wobserver).
All worker and connection information will be added as a page on the web interface.
The current amount of job runners and job success, failure, and reject totals are added to the `/metrics` endpoint.


## Copyright and License

Copyright (c) 2017, SQUARE ENIX LTD.

TaskBunny code is licensed under the [MIT License](LICENSE.md).
