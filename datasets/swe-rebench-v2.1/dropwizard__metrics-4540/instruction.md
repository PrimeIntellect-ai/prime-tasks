`NoopMetricRegistry.NoopTimer::time(Runnable)` should actually run the supplied Runnable
The implementation of `NoopMetricRegistry.NoopTimer`'s `time` method which takes a `Callable<T>` is as follows:
```
        @Override
        public <T> T time(Callable<T> event) throws Exception {
            return event.call();
        }
```

However the implementation of the method overload which takes a `Runnable` is:
```
        @Override
        public void time(Runnable event) {
            // NOP
        }
```
This [latter implementation](https://github.com/dropwizard/metrics/blob/release/4.2.x/metrics-core/src/main/java/com/codahale/metrics/NoopMetricRegistry.java#L433C1-L436C10) is incorrect as the `Runnable` represents important business logic. That is, switching implementations (e.g. during testing) to a `NoopMetricRegistry` actually effects the behaviour of the system!

The method body should be as follows:
```
        @Override
        public void time(Runnable event) {
            [HIDDEN]
        }
```

### Additional contract requirements

- Each call to `NoopTimer.time(Runnable)` must invoke the supplied `Runnable` once.
