# TaskBunny

TaskBunny is a background processing application written in Elixir and uses RabbitMQ as a messaging backend.

## Why RabbitMQ? Why not Erlang process?

It is a fair question and we are not surprised by that.
OTP allows you run background processes conncurrently in distributed manner out of the box.
Why do we need RabbitMQ for background processing?

Well, first of all, if you don't need to persist messages(job requests) outside your system, we suggest you to use Erlang process.
Erlang process and OTP would be always your first choice for backgrond processing in Elixir.

However you might be interested in TaskBunny if you...

- have some reasons to persist and deliver messages outside your Elixir application
- consider using RabbitMQ as background processing message bus

here are some of our reasons:

- We use Docker based deployment and each deploy is immutable and disposable.
- Relatively new to Elixir/Erlang so we don't want to change our infrastructure drastically yet.
- Need some background processes that access to various internal/external systems around the world. We want to controll concurrency and retry interval and see failed processes.

## Project status and versioning

TaskBunny is pre 0.1 and not available on hex.pm yet.
Please be aware that we plan to make breaking changes aggressively without considering backward compatibilities.
We are still discussing about the core design decision like module structure day by day.

However we have decided to opensource this library in some reasons:

- It is used in our production code.
- We noticed quite a few people want to use RabbitMQ for same purpose in their Elixir application.
- We want to hear from community to make this library better.
- Elixir is great but still young. There aren't many examples but we have been helped those examples. Inspired by that, we want to share our work before spending time on polishing.

Hopefully we can make 0.1 release soon but there is nothing preventing you try out this library.

## Getting started

### Requirements

- Elixir 1.4
- Rabbit MQ 3.6.0 or greater

TaskBunny heavily relies on [ampq](https://github.com/pma/amqp) by Paulo Almeida.

### Installation

  1. Add `task_bunny` to your list of dependencies in `mix.exs`:

        def deps do
          [{:task_bunny, github: "shinyscorpion/task_bunny"}]
        end

  1. Ensure `task_bunny` is started before your application (required Elixir 1.3 and before):

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

        # When you use TaskBunny under an umbrella app and each apps needs different job
        # definition, you can prefix jobs like below.

        config :task_bunny, app_a_jobs: [
          [job: AppA.HelloJob, concurrency: 5]
        ]

        config :task_bunny, app_b_jobs: [
          [job: AppB.HolaJob, concurrency: 5]
        ]

### Define job module

use `TaskBunny.Job` module in your job module and define `perform/1` that takes map as an argument.

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

You will see the worker invokes the job and see `SampleJob was invoked with ID=123123` in your logger output.

## Design topics and features

### Queues

TaskBunny declares three queues for a job on RabbitMQ.
If you define `SampleJob` module like above, TaskBunny will define those three queues:

- jobs.sample_job: main worker queue
- jobs.sample_job.retry: queue for retry
- jobs.sample_job.rejected: queue that stores jobs failed more than allowed times

**We are currently discussing about this design decision that queues and workers are tied strongly with job.**

### Concurrency

TaskBunny starts a process for a worker.
A worker listen to one queue and run number of jobs set in config file concurrently.

There is not limit on concurrency on TaskBunny layer.
You want to blance between performance and needs on throttle.

### Retry

TaskBunny retries the job if the job is failed.
In default, it retries 10 times for every 5 minutes.

If you want to change it, you want to overwrite the value on a job module.

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

With this example, it will retry 100 times for every 10 seconds.

If job failed more than `max_retry` times, the payload will be sent to `jobs.[job_name].rejected` queue.
At this moment, TaskBunny doesn't provide any feature accessing to this queue.

Under the hood, TaskBunny uses [dead letter exchanges](https://www.rabbitmq.com/dlx.html) to support retry.

### Timeout

In default, job gets timeout in 2 minutes.
If job doesn't respond more than 2 minutes, worker kills the process and move it to retry queue.

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
What the task does is basically to delete the queues and create them again.
That means existing messages in the queue will be lost so please be aware of it.

```
% mix task_bunny.queue.reset
```

You need to redefine a queue when you want to change retry interval for a queue too.


### Reconnection

TaskBunny automatically try reconnecting to RabbitMQ if the connection is gone.
All workers will be restarted automatically once the new connection is established.


## Copyright and License

Copyright (c) 2017, SQUARE ENIX LTD.

TaskBunny code is licensed under the [MIT License](LICENSE.md).
