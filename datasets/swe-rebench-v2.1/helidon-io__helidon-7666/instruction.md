4.x SE meters should have default scope of `application` instead of no scope
## Environment Details
* Helidon Version: 4.x
* Helidon SE or Helidon MP SE
* JDK version:
* OS:
* Docker version (if applicable):

----------

## Problem Description
In the new Helidon metrics API, each meter can have a different scope (formerly called "registry type" in 3.x) or no scope. Currently, if the developer creates a meter without setting the scope explicitly or without setting the default scope in the `MetricsConfig` then the meter has no scope.

This is different from 3.x (in which the default scope was always `application`.)

For ease of migration, the new metrics API in SE should use `application` as the default scope (unless the developer changes it using `MetricsConfig`).
