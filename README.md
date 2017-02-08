# TaskBunny

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

TaskBunny is pre 0.1 and not available on hex.pm yet.
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

  1. Add `task_bunny` to your list of dependencies in `mix.exs`:

        def deps do
          [{:task_bunny, github: "shinyscorpion/task_bunny"}]
        end

  1. Start `task_bunny` before your application (required Elixir 1.3 and before):

        def application do
          [applications: [:task_bunny]]
        end

  1. Configure hosts and jobs(workers)

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

        # When you use TaskBunny under an umbrella app and each app needs a different job
        # definition, you can prefix jobs like below.

        config :task_bunny, app_a_jobs: [
          [job: AppA.HelloJob, concurrency: 5]
        ]

        config :task_bunny, app_b_jobs: [
          [job: AppB.HolaJob, concurrency: 5]
        ]

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
:ok = TaskBunny.SyncPublisher.push(SampleJob, %{"id" => 123123})
```

The worker invokes the job with `SampleJob was invoked with ID=123123` in your logger output.

## Design topics and features

### Queues

TaskBunny declares three queues for a job on RabbitMQ.
If you define `SampleJob` module like above, TaskBunny will define those three queues:

- jobs.sample_job: main worker queue
- jobs.sample_job.retry: queue for retry
- jobs.sample_job.rejected: queue that stores jobs failed more than allowed times

**We are discussing the design decision about queues and workers being tied strongly with a job.**

### Concurrency

TaskBunny starts a process for a worker.
A worker listens to one queue and runs the number of jobs set in config file concurrently.

There is no limit on concurrency on TaskBunny layer.
You want to balance between performance and needs on throttle.

### Retry

TaskBunny retries the job if the job has failed.
By default, it retries 10 times for every 5 minutes.

If you want to change it, you can overwrite the value on a job module.

```elixir
defmodule SampleJob do
  use TaskBunny.Job
  require Logger

  def perform(%{"id" => id}) do
    Logger.info("SampleJob was invoked with ID=#{id}")
  end

  def max_retry, do: 100
  def retry_interval, do: 10_000
end

```

In this example, it will retry 100 times for every 10 seconds.

If a job fails more than `max_retry` times, the payload is sent to `jobs.[job_name].rejected` queue.
At the moment, TaskBunny doesn't provide any feature for accessing this queue.

Under the hood, TaskBunny uses [dead letter exchanges](https://www.rabbitmq.com/dlx.html) to support retry.

### Timeout

By default, jobs timeout after 2 minutes.
If job doesn't respond for more than 2 minutes, worker kills the process and moves it to retry queue.

You can change the timeout by overwriting `timeout/0` in your job.

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


## Copyright and License

Copyright (c) 2017, SQUARE ENIX LTD.

TaskBunny code is licensed under the [MIT License](LICENSE.md).
