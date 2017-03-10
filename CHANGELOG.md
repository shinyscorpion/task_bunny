# Changelog

## 0.0.1-dev.9

* Update bunch of API interface. Make return values and exceptions consistent. [#25](https://github.com/shinyscorpion/task_bunny/pull/25)

## 0.0.1-dev.8

* Fix a bug on Job.enqueue [#24](https://github.com/shinyscorpion/task_bunny/pull/24)

## 0.0.1-dev.7

This will be the last feature release before 0.1.0.

**You need to change your config files after updating to this version**

* Decouple queues and jobs. We now have a new syntax on config file. [#21](https://github.com/shinyscorpion/task_bunny/pull/21)
* Change `Job.retry_interval/0` to `Job.retry_interval/1` and take failure count. [#23](https://github.com/shinyscorpion/task_bunny/pull/23)

## 0.0.1-dev.6

* `TaskBunny.WorkerSupervisor/1` and `TaskBunny.WorkerSupervisor/2` to shut down
 all workers gracefully. [#20](https://github.com/shinyscorpion/task_bunny/pull/20)

## 0.0.1-dev.5

**Please reset your queues after upgrading TaskBunny. This updated queue configuration**

* Rename SyncPublisher module to Publisher and clean up the interface. [#18](https://github.com/shinyscorpion/task_bunny/pull/18)
* Add error logs to message body when retrying. Updated the logic how TaskBunny retries [#17](https://github.com/shinyscorpion/task_bunny/pull/17)

## 0.0.1-dev.4

* New API: Job.enqueue/2 [#14](https://github.com/shinyscorpion/task_bunny/pull/14)
* Update message format to include job and wrap argument with payload key. [#13](https://github.com/shinyscorpion/task_bunny/pull/13)

## 0.0.1-dev.3

* Add [Wobserver](https://github.com/shinyscorpion/wobserver) support.

## 0.0.1-dev.2

* Switch back amqp library to the official version that supports OTP 19

## 0.0.1-dev.1

* Preparing the first official release

