# TaskBunny

[![Hex.pm](https://img.shields.io/hexpm/v/task_bunny.svg "Hex")](https://hex.pm/packages/task_bunny)
[![Build Status](https://travis-ci.org/shinyscorpion/task_bunny.svg?branch=master)](https://travis-ci.org/shinyscorpion/task_bunny)
[![Inline docs](http://inch-ci.org/github/shinyscorpion/task_bunny.svg?branch=master)](http://inch-ci.org/github/shinyscorpion/task_bunny)
[![Deps Status](https://beta.hexfaktor.org/badge/all/github/shinyscorpion/task_bunny.svg)](https://beta.hexfaktor.org/github/shinyscorpion/task_bunny)
[![Hex.pm](https://img.shields.io/hexpm/l/task_bunny.svg "License")](LICENSE.md)

TaskBunny is a background processing application written in Elixir and uses RabbitMQ as a messaging backend.

[API Reference](https://hexdocs.pm/task_bunny/)

## Use cases

Although TaskBunny provides similar features to popular background processing libraries in other languages such as Resque, Sidekiq, RQ etc., you might not need it for a same reason.
Erlang process or GenServer would always be your first choice for background processing in Elixir.

However you might want to try out TaskBunny in the following cases:

- You want to separate a background processing concern from your phoenix application
- You use container based deployment such as Heroku, Docker etc. and each deploy is immutable and disposable
- You want to have a control on retry and its interval on background job processing
- You want to schedule the job execution time
- You want to use a part of functionalities TaskBunny provides to talk to RabbitMQ
- You want to enqueue jobs from other system via RabbitMQ
- You want to control the concurrency to avoid making too much traffic


## Getting started

### 1. Check requirements

- Elixir 1.4+
- RabbitMQ 3.6.0 or greater

### 2. Install TaskBunny

Edit `mix.exs` and add `task_bunny` to your list of dependencies and applications:

```elixir
def deps do
  [{:task_bunny, "~> 0.3.2"}]
end

def application do
  [applications: [:task_bunny]]
end
```

Then run `mix deps.get`.

### 3. Configure TaskBunny

Configure hosts and queues:

```elixir
config :task_bunny, hosts: [
  default: [connect_options: "amqp://localhost?heartbeat=30"]
]

config :task_bunny, queue: [
  namespace: "task_bunny.",
  queues: [[name: "normal", jobs: :default]]
]
```

### 4. Define TaskBunny job

Use `TaskBunny.Job` module in your job module and define `perform/1` that takes a map as an argument.

```elixir
defmodule HelloJob do
  use TaskBunny.Job
  require Logger

  def perform(%{"name" => name}) do
    Logger.info("Hello #{name}")
    :ok
  end
end
```

Make sure you return `:ok` or `{:ok, something}` when the job was successfully processed.
Otherwise TaskBunny would treat the job as failed and move it to retry queue.

### 5. Enqueueing TaskBunny job

Then enqueue a job

```elixir
HelloJob.enqueue!(%{"name" => "Cloud"})
```

The worker invokes the job with `Hello Cloud` in your logger output.

## Queues

#### Worker queue and sub queues

TaskBunny declares four queues for each worker queue on RabbitMQ.

```elixir
config :task_bunny, queue: [
  namespace: "task_bunny."
  queues: [
    [name: "normal", jobs: :default]
  ]
]
```

If have a config like above, TaskBunny will define these four queues on RabbitMQ:

- task_bunny.normal: main worker queue
- task_bunny.normal.retry: queue for retry
- task_bunny.normal.rejected: queue that stores jobs failed more than allowed times
- task_bunny.normal.delay: queue that stores jobs that are performed in the future


#### Reset queues

TaskBunny provides a mix task to reset queues.
This task deletes the queues and creates them again.
Existing messages in the queue will be lost so please be aware of this.

```
% mix task_bunny.queue.reset
```

You need to redefine a queue when you want to change the retry interval for a queue.


#### Umbrella app

When you use TaskBunny under an umbrella app and each apps needs a different queue definition, you can prefix config key like below so that it doesn't overwrite the other configuration.
_For more granular control (starting a subset of queues) see [Control Startup](#Control-Startup) under Connection management_

```elixir
  config :task_bunny, app_a_queue: [
    namespace: "app_a.",
    queues: [
      [name: "normal", jobs: "AppA.*"]
    ]
  ]

  config :task_bunny, app_b_queue: [
    namespace: "app_b.",
    queues: [
      [name: "normal", jobs: "AppB.*"]
    ]
  ]
```


## Enqueue job

#### Enqueue

`TaskBunny.Job` will define `enqueue/1` and `enqueue!/1` to your job module.
Like other Elixir libraries, `enqueue!/1` is similar to `enqueue/1` but raises
an exception when it gets an error during the enqueue.

You can also use `TaskBunny.Job.enqueue/2` which takes a module as a first
argument. The two examples below will give you the same result.

```elixir
SampleJob.enqueue!()
TaskBunny.Job.enqueue!(SampleJob)
```

First expression is concise and preferred but the later expression lets you
enqueue the job without defining job module.
TaskBunny takes the module just as atom and doesn't check module existence when
it enqueues.
It is useful when you have separate applications for enqueueing and performing.

#### Schedule job

When you don't want to perform the job immediately you can use `delay` options
when you enqueue the job.

```elixir
SampleJob.enqueue!(delay: 10_000)
```

It will enqueue the job to the worker queue in 10 seconds.

When you use `delay` option it enqueues the job to the delay queue.
The job will be moved to the worker queue after the specific time.

The move between those queues will be handled by RabbitMQ so the job will be enqueued safely even if your application dies after the call.

#### Enqueue job from other system

The message should be encoded in JSON format and set job and payload(argument).
For example:

```javascript
{
  "job": "YourApp.HelloJob",
  "payload": {"name": "Aerith"}
}
```

Then send the message to the worker queue - TaskBunny will process it.

#### Select queue

TaskBunny looks up config and chooses a right queue for the job.

```elixir
config :task_bunny, queue: [
  queues: [
    [name: "default", jobs: :default],
    [name: "fast_track", jobs: [YourApp.RushJob, YourApp.HurryJob],
    [name: "analytics", jobs: "Analytics.*"]
  ]
]
```

You can configure it with module name(atom), string (support wildcard) or list of them.
If the job matches one of them the queue will be chosen.
If the doesn't match any the queue with :default will be chosen.

```elixir
YourApp.RushJob.enqueue(payload) #=> "fast_track"
Analytics.MiningJob.enqueue(payload) #=> "analytics"
YourApp.HelloJob.enqueue(payload) #=> "default"
```

If you pass the queue option TaskBunny will use it.

```elixir
YourApp.HelloJob.enqueue(payload, queue: "fast_track") #=> "fast_track"
```

## Workers

#### What is worker?

TaskBunny worker is a GenServer that processes jobs and handles errors.
A worker listens to a single queue, receives messages(jobs) from it and invokes jobs to perform.

#### Concurrency

By default a TaskBunny worker runs two jobs concurrently.
You can change the concurrency with the config.

```elixir
config :task_bunny, queue: [
  namespace: "task_bunny."
  queues: [
    [name: "default", jobs: :default, worker: [concurrency: 1]],
    [name: "analytics", jobs: "Analytics.*", worker: [concurrency: 10]]
  ]
]
```

The concurrency is set per an application.
If you run your application on five different hosts with above configuration,
there can be 55 jobs performing simultaneously in total.

#### Disable storing rejected jobs in a queue

By default, if a job fails more than `max_retry` times, the payload is sent to `[namespace].[job_name].rejected` queue.
You can disable this behavior in the config by setting `store_rejected_jobs` worker parameter to `false` (defaults to `true`).
This might be useful when rejected jobs queue is never consumed, thus making the queue grow infinitely.

```elixir
config :task_bunny, queue: [
  namespace: "task_bunny."
  queues: [
    [name: "default", jobs: :default, worker: [concurrency: 1, store_rejected_jobs: false]]
  ]
]
```

With above, worker does not store rejected jobs. However, `on_reject` callback is still called when a job gets rejected.

#### Disable worker

You can disable workers starting with your application by setting `1`, `TRUE` or `YES` to `TASK_BUNNY_DISABLE_WORKER` environment variable.

```
% TASK_BUNNY_DISABLE_WORKER=1 mix phoenix.server
```

You can also disable workers in the config.

```elixir
config :task_bunny, disable_worker: true
```

You can also disable worker running for a specific queue with the config.

```elixir
config :task_bunny, queue: [
  namespace: "task_bunny."
  queues: [
    [name: "default", jobs: :default],
    [name: "analytics", jobs: "Analytics.*", worker: false]
  ]
]
```

With above, TaskBunny starts only a worker for the default queue.

## Control job execution

#### Retry

TaskBunny marks the job failed when:

- job raises an exception or exits during `perform`
- `perform` doesn't return `:ok` or `{:ok, something}`
- `perform` times out.

TaskBunny retries the job automatically if the job has failed.
By default, it retries 10 times for every 5 minutes.

If you want to change it, you can override the value on a job module.

```elixir
defmodule FlakyJob do
  use TaskBunny.Job
  require Logger

  def max_retry, do: 100
  def retry_interval(_), do: 10_000

  ...
end
```

In this example, it will retry 100 times for every 10 seconds.
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

If a job fails more than `max_retry` times, the payload is sent to `jobs.[job_name].rejected` queue.

When a job gets rejected the `on_reject` callback is called. By default it does nothing but you can override it.
It's useful to execute recovery actions when a job fails (like sending an email to a customer for instance)

It receives the body containing the payload of the rejected job plus the full error trace. It returns :ok

```elixir
defmodule FlakyJob do
  use TaskBunny.Job
  require Logger

  def on_reject(_body) do
     ...

     :ok
  end
  ...
end
```

#### Immediately Reject

TaskBunny can mark a job as rejected without retrying when `perform` returns `:reject` or `{:reject, something}`

In this case any `max_retry` config is ignored.

#### Timeout

By default, jobs timeout after 2 minutes.
If job doesn't respond for more than 2 minutes, worker kills the process and moves it to retry queue.

You can change the timeout by overriding `timeout/0` in your job.

```elixir
defmodule SlowJob do
  use TaskBunny.Job
  def timeout, do: 300_000

  ...
end
```

## Connection management

TaskBunny provides an extra layer on top of the [amqp](https://github.com/pma/amqp) connection module.

#### Configuration

TaskBunny automatically connects to RabbitMQ hosts in the config at the start of
the application.

TaskBunny forwards `connect_options` to [AMQP.Connection.open/1](https://hexdocs.pm/amqp/AMQP.Connection.html#open/1).

```elixir
config :task_bunny, hosts: [
  default: [
    connect_options: "amqp://rabbitmq.example.com?heartbeat=30"
  ],
  legacy: [
    connect_options: [
      host: "legacy.example.com",
      port: 15672,
      username: "guest",
      password: "bunny"
    ]
  ]
]

```

`:default` host has a special meaning on TaskBunny: TaskBunny would select `:default`
host when you didn't specify the host.

```elixir
assert TaskBunny.Connection.get_connection() == TaskBunny.Connection.get_connection(:default)
```

You can specify the host to the queue:

```elixir
config :task_bunny, queue: [
  queues: [
    [name: "normal", jobs: "MainApp.*"], # => :default host
    [name: "normal", jobs: "Legacy.*", host: :legacy]
  ]
]
```

If you don't want to start TaskBunny automatically in a specific environment, set `true` to `disable_auto_start` in the config:

```elixir
config :task_bunny, disable_auto_start: true
```

##### Control Startup
If you wan to control the startup process yourself, disable `task_bunny` as a runtime dependency and invoke [TaskBunny.Supervisor](./lib/task_bunny/supervisor.ex) yourself:

```elixir
# mix.exs
defp deps do
[
  {:task_bunny, "~> 0.3.2", runtime: false}
]
end
```

Add `TaskBunny.Supervisor` to your supervisor tree
```elixir
# Somewhere in you application
children = [
      supervisor(TaskBunny.Supervisor,
        [
          TaskBunny.Supervisor,
          TaskBunny.WorkerSupervisor,
          :publisher,
          [queues: [namespace: "pest_routes"]] # empty list will start all queues in configs, you can also name queues specifically: [queues: ["mynamespace.myqueue.name"]]
        ]
      )
      # ... anything else. (i.e. Ecto.Repo, etc) 
    ]
```


#### Get connection

TaskBunny provides two ways to access the connections.
Most of time you want to use `Connection.get_connection/1` or
`Connection.get_connection!/1` that returns the connection synchronously.

```elixir
conn = TaskBunny.Connection.get_connection()
legacy = TaskBunny.Connection.get_connection(:legacy)
```

TaskBunny also provides asynchronous API `Connection.subscribe_connection/1`.
See the [API documentation](https://hexdocs.pm/task_bunny/TaskBunny.Connection.html) for more details.

#### Reconnection

TaskBunny automatically tries reconnecting to RabbitMQ if the connection is gone.
All workers will restart automatically once the new connection is established.

TaskBunny aims to provide zero hassle and recover automatically regardless how
long the host takes to come back and accessible.

## Failure backends

By default, when the error occurs during the job execution TaskBunny reports it
to Logger. If you want to report the error to different services, you can configure
your custom failure backend.

```elixir
config :task_bunny, failure_backend: [YourApp.CustomFailureBackend]
```

You can also report the errors to the multiple backends. For example, if you
want to use our default Logger backend with your custom backend you can
configure like below:

```elixir
config :task_bunny, failure_backend: [
  TaskBunny.FailureBackend.Logger,
  YourApp.CustomFailureBackend
]
```

Check out the implementation of [TaskBunny.FailureBackend.Logger](https://github.com/shinyscorpion/task_bunny/blob/master/lib/task_bunny/failure_backend/logger.ex) to learn how to write your custom failure backend.

#### Implementations

- [Rollbar backend](https://github.com/shinyscorpion/task_bunny_rollbar)
- [Sentry backend](https://github.com/Homepolish/task_bunny_sentry)

(Send us a pull request if you want to add other implementation)

## Monitoring

#### RabbitMQ plugins

RabbitMQ supports a variety of [plugins](http://www.rabbitmq.com/plugins.html).
If you are not familiar with them we recommend you to look into those.

The following plugins will help you use RabbitMQ with TaskBunny.

* [Management Plugin](http://www.rabbitmq.com/management.html): provides an HTTP-based API for management and monitoring of your RabbitMQ server, along with a browser-based UI and a command line tool, rabbitmqadmin.
* [Shovel Plugin](http://www.rabbitmq.com/shovel.html): helps you to move messages(job) from a queue to another queue.

#### Wobserver integration

TaskBunny automatically integrates with [Wobserver](https://github.com/shinyscorpion/wobserver).
All worker and connection information will be added as a page on the web interface.
The current amount of job runners and job success, failure, and reject totals are added to the `/metrics` endpoint.


## Copyright and License

Copyright (c) 2017, SQUARE ENIX LTD.

TaskBunny code is licensed under the [MIT License](LICENSE.md).
