# Changelog

We are still discussing backward incompatible changes. Please see [Gihub issues](https://github.com/shinyscorpion/task_bunny/issues) for the details.

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

