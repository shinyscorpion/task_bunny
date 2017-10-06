# Changelog

## 0.2.2

* Fix typespec [#42](https://github.com/shinyscorpion/task_bunny/pull/42)

## 0.2.1

* Expose `FailureBackend.Logger.get_job_error_message/1`. [#37](https://github.com/shinyscorpion/task_bunny/pull/37)

## 0.2.0

Support the failure backend extension.
You can implement your own job failure reporting module.

There is no change needed in your code for the changes and TaskBunny reports
the job errors to Logger by default.
There are slight changes on the message format and its contents.

See [#36](https://github.com/shinyscorpion/task_bunny/pull/36) for the details.

## 0.1.2

* Disable workers with the config. [#35](https://github.com/shinyscorpion/task_bunny/pull/35)

## 0.1.1

* Fix the issue with multiple hosts. [#33](https://github.com/shinyscorpion/task_bunny/pull/33)

## 0.1.0

* No change from 0.1.0-rc.3

## 0.1.0-rc.3

* Update README
* Declare the queues on application start. Don't declare the queues on enqueue.

## 0.1.0-rc.2

* Support ENV var to disable TaskBunny worker. [#29](https://github.com/shinyscorpion/task_bunny/pull/29)
* Support scheduled job execution. [#30](https://github.com/shinyscorpion/task_bunny/pull/30)
* Updated amqp library to 0.2.0.

## 0.1.0-rc.1

* Updated documentation

## 0.0.1-dev.10

* Fixed a wrong type spec.

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

