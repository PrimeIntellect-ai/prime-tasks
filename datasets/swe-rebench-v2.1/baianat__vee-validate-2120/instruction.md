ValidationProvider `persist` behavior is different than the directive
Reported in #1961, the `persist` behavior for the Provider doesn't work quite the same as the directive. Both restore the errors to the field just fine when it's re-mounted.

In the directives, errors are visible even after unmounting.

In the observer context, errors are not visible after unmounting as they are stored internally by non-reactive storage.

The Observer context should "keep" the errors visible indefinitely.
